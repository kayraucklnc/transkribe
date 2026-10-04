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
    private static let minimumSamples = Int(PCMStore.sampleRate * 0.3)
    private static let maximumDuration: Duration = .seconds(600)

    private unowned let model: AppModel
    private let panel = DictationPanelHost()
    private var capture: DictationCapture?
    private var engine: (key: String, engine: any SpeechEngine)?
    private var prepareTask: Task<Void, Error>?
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
        shortcutToken = HotKeys.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.toggle()
        }
        shortcutIsAvailable = shortcutToken != nil
    }

    // MARK: - Flow

    func toggle() {
        switch phase {
        case .hidden, .finished: start()
        case .listening: finish()
        case .transcribing: break
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
        releaseSessionKeys()
        showsHint = false
        phase = .transcribing
        let samples = capture?.stop() ?? []
        capture = nil
        workTask?.cancel()
        guard samples.count >= Self.minimumSamples else {
            end(.nothingHeard)
            return
        }
        let vocabulary = model.settings.vocabulary
        workTask = Task {
            do {
                let engine = prepareEngine()
                try await prepareTask?.value
                let output = try await engine.transcribe(samples: samples) { _ in }
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
            return model.engine
        }
        let key = "\(quality.rawValue)|\(settings.languages)|\(settings.vocabulary)"
        if let engine, engine.key == key { return engine.engine }
        let fresh = AppModel.makeEngine(settings: settings, quality: quality, european: model.european)
        engine = (key, fresh)
        prepareTask = Task { try await fresh.prepare { _ in } }
        return fresh
    }

    /// A separate model is a lot of memory: let it go after a few quiet minutes.
    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled, phase == .hidden else { return }
            engine = nil
            prepareTask = nil
        }
    }
}
