import AppKit
import Carbon.HIToolbox
import Observation
import TranskribeCore

/// Speak anywhere: a shortcut opens a small listening pill, Return types what you said into
/// the focused field (or copies it when there's no field), Escape throws it away.
@Observable @MainActor
final class DictationController {
    enum Phase: Equatable {
        case hidden
        case listening
        case transcribing
        case finished(Outcome)
    }

    enum Outcome: Equatable {
        case pasted
        case copied
        case nothingHeard
        case failed(String)
    }

    private(set) var phase: Phase = .hidden
    /// Recent loudness (0...1), newest last, for the waveform.
    private(set) var levels: [Double] = Array(repeating: 0, count: DictationController.historyLength)
    /// Shown briefly below the pill the first few times.
    private(set) var showsHint = false
    /// What the chosen model is doing before it can listen (downloading or loading), if anything.
    private(set) var setup: TranscriptionEngine.Preparation?
    var setupProgress: Double? {
        if case .downloading(let fraction) = setup { return fraction }
        return nil
    }
    var isLoadingModel: Bool {
        if case .loading = setup { return true }
        return false
    }
    /// The faster model was used this time because the chosen one is still downloading.
    private(set) var usedFallback = false

    var speed: DictationSpeed {
        didSet { UserDefaults.standard.set(speed.rawValue, forKey: Self.speedKey) }
    }

    /// Any key combination the user records; nil turns the shortcut off.
    var shortcut: KeyCombo? {
        didSet {
            if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: Self.shortcutKey)
            } else {
                UserDefaults.standard.set(Data(), forKey: Self.shortcutKey)
            }
            installShortcut()
        }
    }

    /// False when another app already owns the chosen shortcut.
    private(set) var shortcutIsAvailable = true

    static let historyLength = 24
    private static let speedKey = "dictationSpeed"
    private static let shortcutKey = "dictationKeyCombo"
    private static let usesKey = "dictationUses"
    private static let holdThreshold: TimeInterval = 0.6
    private static let transcriptionTimeout: Duration = .seconds(90)
    private var startedAt = Date.distantPast
    private static let minimumSamples = Int(PCMStore.sampleRate * 0.3)
    private static let maximumDuration: Duration = .seconds(600)

    private unowned let model: AppModel
    private let panel = DictationPanelHost()
    private var capture: DictationCapture?
    private var engine: (key: String, engine: any SpeechEngine)?
    private var prepareTask: Task<Void, Error>?
    private var engineReady = false
    private var workTask: Task<Void, Never>?
    private var releaseTask: Task<Void, Never>?
    private var shortcutToken: UInt32?
    private var sessionTokens: [UInt32] = []

    init(model: AppModel) {
        self.model = model
        speed = UserDefaults.standard.string(forKey: Self.speedKey).flatMap(DictationSpeed.init) ?? .balanced
        shortcut = Self.savedShortcut()
    }

    // MARK: - Shortcut

    private static func savedShortcut() -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: shortcutKey) else { return .optionSpace }
        return data.isEmpty ? nil : (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? .optionSpace
    }

    /// Stops the shortcut firing while a new one is being recorded.
    func suspendShortcut() {
        HotKeys.shared.unregister(shortcutToken)
        shortcutToken = nil
    }

    func installShortcut() {
        HotKeys.shared.unregister(shortcutToken)
        shortcutToken = nil
        guard let shortcut else {
            shortcutIsAvailable = true
            return
        }
        shortcutToken = HotKeys.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers,
                                                onRelease: { [weak self] in self?.shortcutReleased() }) { [weak self] in
            self?.toggle()
        }
        shortcutIsAvailable = shortcutToken != nil
    }

    // MARK: - Flow

    /// Tap the shortcut to start and again to finish, or hold it while you talk and let go.
    func toggle() {
        switch phase {
        case .hidden, .finished: start()
        case .listening:
            // A second press right after starting is a bounce, not "I'm done".
            guard Date().timeIntervalSince(startedAt) > 0.4 else { return }
            finish()
        case .transcribing: break
        }
    }

    private func shortcutReleased() {
        // Held for a while: push-to-talk, so letting go means done.
        if phase == .listening, Date().timeIntervalSince(startedAt) > Self.holdThreshold { finish() }
    }

    /// Preloads the dictation model in the background so the first take is instant.
    func warmUp() {
        Task {
            try? await Task.sleep(for: .seconds(8))
            guard phase == .hidden else { return }
            prepareEngine()
        }
    }

    func start() {
        // The microphone is already in use by the recording; don't fight over it.
        guard !model.isRecording else { return NSSound.beep() }
        workTask?.cancel()
        releaseTask?.cancel()
        levels = Array(repeating: 0, count: Self.historyLength)
        let uses = UserDefaults.standard.integer(forKey: Self.usesKey)
        showsHint = uses < 5
        UserDefaults.standard.set(uses + 1, forKey: Self.usesKey)
        phase = .listening
        startedAt = Date()
        panel.show(controller: self)
        claimSessionKeys()

        let capture = DictationCapture()
        self.capture = capture
        workTask = Task {
            do {
                try await RecordingSession.requestPermissions(for: .microphone)
                guard phase == .listening else { return }
                try capture.start { [weak self] rms in
                    let level = DictationLevel.normalized(rms: rms)
                    Task { @MainActor in self?.push(level) }
                }
                prepareEngine()
                try await Task.sleep(for: Self.maximumDuration)
                if phase == .listening { finish() }
            } catch is CancellationError {
            } catch {
                end(.failed(error.localizedDescription))
            }
            if showsHint {
                try? await Task.sleep(for: .seconds(3))
                showsHint = false
            }
        }
    }

    func finish() {
        guard phase == .listening else { return }
        claimEscapeOnly()
        showsHint = false
        phase = .transcribing
        let samples = capture?.stop() ?? []
        capture = nil
        workTask?.cancel()
        let speech = DictationAudio.trimmed(samples)
        saveLastTake(samples)
        guard speech.count >= Self.minimumSamples else {
            end(.nothingHeard)
            return
        }
        let vocabulary = model.settings.vocabulary
        workTask = Task {
            do {
                let engine = try await readyEngine()
                let output = try await withTimeout(Self.transcriptionTimeout) {
                    try await engine.transcribe(samples: speech) { _ in }
                }
                let text = DictationText.finalize(output.segments, vocabulary: vocabulary)
                guard !text.isEmpty else { return end(.nothingHeard) }
                let result = await TextInserter.insert(text)
                end(result == .pasted ? .pasted : .copied)
            } catch is CancellationError {
            } catch {
                end(.failed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        releaseSessionKeys()
        _ = capture?.stop()
        capture = nil
        workTask?.cancel()
        hide()
    }

    // MARK: - Helpers

    private func push(_ level: Double) {
        guard phase == .listening else { return }
        // Rise quickly, fall gently, like a VU meter.
        let previous = levels.last ?? 0
        let smoothed = level > previous ? level : previous * 0.6 + level * 0.4
        levels = Array(levels.dropFirst()) + [smoothed]
    }

    private func end(_ outcome: Outcome) {
        releaseSessionKeys()
        phase = .finished(outcome)
        if case .failed = outcome { NSSound.beep() }
        workTask = Task {
            try? await Task.sleep(for: outcome == .pasted ? .seconds(0.9) : .seconds(1.8))
            guard !Task.isCancelled else { return }
            hide()
        }
        scheduleRelease()
    }

    private func hide() {
        phase = .hidden
        panel.hide()
    }

    /// Return and Escape belong to the pill only while it's listening.
    private func claimSessionKeys() {
        releaseSessionKeys()
        let keys: [(Int, () -> Void)] = [
            (kVK_Return, { [weak self] in self?.finish() }),
            (kVK_ANSI_KeypadEnter, { [weak self] in self?.finish() }),
            (kVK_Escape, { [weak self] in self?.cancel() }),
        ]
        sessionTokens = keys.compactMap { HotKeys.shared.register(keyCode: $0.0, modifiers: 0, action: $0.1) }
    }

    /// While the words are being worked out, Esc still cancels.
    private func claimEscapeOnly() {
        releaseSessionKeys()
        if let token = HotKeys.shared.register(keyCode: kVK_Escape, modifiers: 0, action: { [weak self] in self?.cancel() }) {
            sessionTokens = [token]
        }
    }

    private func releaseSessionKeys() {
        sessionTokens.forEach { HotKeys.shared.unregister($0) }
        sessionTokens = []
    }

    /// Reuses the app's engine when it's the same setup and idle; otherwise keeps a separate one
    /// so dictation never waits behind a long transcription.
    @discardableResult
    private func prepareEngine() -> any SpeechEngine {
        let settings = model.settings
        let quality = speed.quality(for: settings.languages)
        if quality == settings.quality, !model.isTranscribingSomething {
            engine = nil
            prepareTask = nil
            engineReady = true
            return model.engine
        }
        let key = "\(quality.rawValue)|\(settings.languages)|\(settings.vocabulary)"
        if let engine, engine.key == key { return engine.engine }
        // Short takes don't need the separate European model; Whisper alone is quicker to load and answer.
        let fresh = AppModel.makeEngine(settings: settings, quality: quality, european: nil)
        engine = (key, fresh)
        engineReady = false
        prepareTask = Task { [weak self] in
            try await fresh.prepare { state in
                Task { @MainActor in self?.setup = state }
            }
            await MainActor.run {
                self?.engineReady = true
                self?.setup = nil
            }
        }
        return fresh
    }

    /// The chosen engine if it's ready. If it's still downloading (first use of a new speed),
    /// the app's own model answers now when it's ready, and the download carries on.
    private func readyEngine() async throws -> any SpeechEngine {
        let chosen = prepareEngine()
        usedFallback = false
        guard !engineReady else { return chosen }
        if setupProgress != nil, model.modelPreparation == .ready, !model.isTranscribingSomething {
            usedFallback = true
            return model.engine
        }
        do {
            try await prepareTask?.value
        } catch {
            engine = nil
            prepareTask = nil
            setup = nil
            throw error
        }
        return chosen
    }

    /// Keeps the most recent take on this Mac, to check what the microphone heard.
    private func saveLastTake(_ samples: [Float]) {
        let url = TranscriptStore.defaultRoot.appendingPathComponent("Dictation/last-take.wav")
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? DictationAudio.writeWAV(samples, to: url)
        }
    }

    /// A separate model is a lot of memory: let it go after a few quiet minutes.
    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(for: .seconds(1800))
            guard !Task.isCancelled, phase == .hidden else { return }
            engine = nil
            prepareTask = nil
        }
    }
}

struct DictationTimeout: LocalizedError {
    var errorDescription: String? { "That took too long. Try again." }
}

/// Runs `work`, giving up after `limit`.
private func withTimeout<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw DictationTimeout()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
