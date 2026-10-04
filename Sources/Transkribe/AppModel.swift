import AppKit
import Observation
import TranskribeCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    enum RecordingState: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case stopping
    }

    enum Activity: Equatable {
        case transcribing(Double)
        /// Transcribing a recording that is still running.
        case live
        /// Waiting for the Mac to have resources to spare; resumes on its own.
        case paused(String)
        case identifyingSpeakers
    }

    struct Alert: Identifiable {
        let id = UUID()
        var message: String
        var settingsURL: URL?
    }

    var transcripts: [Transcript] = []
    var selection: Transcript.ID? {
        didSet { UserDefaults.standard.set(selection?.uuidString, forKey: Self.selectionKey) }
    }
    var query = ""
    /// A moment to scroll to and briefly highlight in the open conversation (from search).
    var focus: (id: Transcript.ID, time: TimeInterval, token: UUID)?
    var alert: Alert?
    var toast: String?

    var modelPreparation: TranscriptionEngine.Preparation?
    var activity: [Transcript.ID: Activity] = [:]
    /// When the current work on a transcript began, for time-left estimates.
    var activityStarted: [Transcript.ID: Date] = [:]

    var recordingState: RecordingState = .idle
    /// Recent input levels (0...1), newest last, for the live waveform.
    var levels: [Float] = Array(repeating: 0, count: AppModel.levelHistory)
    var recordingSource: RecordingSource {
        didSet { UserDefaults.standard.set(recordingSource.rawValue, forKey: Self.sourceKey) }
    }

    static let levelHistory = 48
    let store: TranscriptStore
    /// The engine for new transcriptions, built from `settings`.
    private(set) var engine: any SpeechEngine
    /// Shared so the European model loads once, whichever engine uses it.
    let european = ParakeetEngine()
    var settings: TranscriptionSettings {
        didSet {
            settings.save()
            if oldValue.quality != settings.quality || oldValue.languages != settings.languages
                || oldValue.vocabulary != settings.vocabulary {
                engine = Self.makeEngine(settings: settings, quality: settings.quality, european: european)
                preloadModel()
            }
        }
    }
    var enhanceTask: Task<Void, Never>?
    var people: [Person] = []
    let peopleStore = PeopleStore()
    /// The person whose page is open (when no conversation is).
    var selectedPerson: Person.ID?
    /// Set when a recording should join a conversation and/or be linked to a person.
    var pendingFollowUp: (transcript: Transcript.ID?, person: Person.ID?)?
    var enhancingID: Transcript.ID?
    let diarizer: DiarizationEngine
    var session: (recorder: RecordingSession, transcript: Transcript)?
    /// Transcription that runs alongside the current recording.
    var live: (task: Task<Void, Error>, sources: [LiveAudioSource])?
    /// The transcript being recorded right now, shown live.
    var liveRecordingID: Transcript.ID?
    var startFailure: Error?
    var queueTask: Task<Void, Never>?
    var transcribingID: Transcript.ID?
    private var toastTask: Task<Void, Never>?
    private static let sourceKey = "recordingSource"
    private static let selectionKey = "selectedTranscript"

    init(store: TranscriptStore = TranscriptStore(rootDirectory: TranscriptStore.defaultRoot),

         diarizer: DiarizationEngine = DiarizationEngine()) {
        self.store = store
        let settings = TranscriptionSettings.load()
        self.settings = settings
        self.engine = Self.makeEngine(settings: settings, quality: settings.quality, european: european)
        self.diarizer = diarizer
        recordingSource = UserDefaults.standard.string(forKey: Self.sourceKey).flatMap(RecordingSource.init) ?? .microphone
        do {
            _ = try store.recoverInterruptedRecordings()
            transcripts = try store.loadAll()
        } catch {
            show(error)
        }
        loadPeople()
        let saved = UserDefaults.standard.string(forKey: Self.selectionKey).flatMap(UUID.init)
        selection = transcripts.first { $0.id == saved }?.id
        FileImport.removeTemporaryCopies()
        if settings.completedOnboarding {
            processQueue()
            preloadModel()
        }
        startEnhancing()
    }

    func finishOnboarding() {
        processQueue()
        preloadModel()
    }

    /// Instant → macOS's recognizer; Balanced/Best → Whisper (turbo / full), with the European
    /// model for English, Italian and similar languages.
    static func makeEngine(settings: TranscriptionSettings, quality: TranscriptionQuality, european: ParakeetEngine) -> any SpeechEngine {
        let languages = Set(settings.languages.isEmpty ? Array(TranscriptionEngine.supportedLanguages) : settings.languages)
        let usesEuropean = languages.contains(where: EngineCatalog.usesEuropeanModel)
        switch quality {
        case .instant:
            if #available(macOS 26, *), AppleSpeechEngine.isAvailable {
                return AppleSpeechEngine(languages: Array(languages), vocabulary: settings.vocabulary)
            }
            fallthrough
        case .balanced:
            return TranscriptionEngine(languages: languages, vocabulary: settings.vocabulary, european: usesEuropean ? european : nil)
        case .best:
            return TranscriptionEngine(model: TranscriptionEngine.bestModel, languages: languages,
                                       vocabulary: settings.vocabulary, european: usesEuropean ? european : nil)
        }
    }

    // MARK: - Queries

    var filteredTranscripts: [Transcript] {
        transcripts.filter { TranscriptSearch.matches($0, query: query) }
    }

    var selectedTranscript: Transcript? {
        transcripts.first { $0.id == selection }
    }

    func transcript(_ id: Transcript.ID) -> Transcript? {
        transcripts.first { $0.id == id }
    }

    var isRecording: Bool { recordingState != .idle }

    // MARK: - Import

    func importFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                await importFile(url)
            }
        }
    }

    private func importFile(_ url: URL) async {
        let isVideo = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
        let needsExtraction = isVideo || url.pathExtension.isEmpty
        let fileName = needsExtraction ? "audio.m4a" : "audio.\(url.pathExtension.lowercased())"
        var transcript = Transcript(title: TitleGenerator.title(forFile: url), tracks: [AudioTrack(fileName: fileName)])
        let destination = store.audioURL(for: transcript, track: transcript.tracks[0])
        do {
            try store.prepareDirectory(for: transcript)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if needsExtraction {
                try await AudioDecoder.extractAudio(from: url, to: destination)
            } else {
                _ = try await AudioDecoder.duration(of: url) // fail fast on unreadable files
                try await Task.detached { try FileManager.default.copyItem(at: url, to: destination) }.value
            }
            transcript.duration = try await AudioDecoder.duration(of: destination)
            try store.save(transcript)
        } catch {
            try? store.delete(transcript)
            show(message: "Couldn't open “\(url.lastPathComponent)”. \(error.localizedDescription)")
            return
        }
        insert(transcript)
    }

    func insert(_ transcript: Transcript) {
        transcripts.insert(transcript, at: 0)
        selection = transcript.id
        processQueue()
    }

    // MARK: - Editing

    func rename(_ id: Transcript.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id, persist: true) { $0.title = trimmed }
    }

    func renameSpeaker(_ speaker: Int, in id: Transcript.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id, persist: true) { $0.speakerNames[speaker] = trimmed.isEmpty ? nil : trimmed }
    }

    /// Opens a conversation scrolled to `time`, e.g. from a search result.
    func open(_ id: Transcript.ID, at time: TimeInterval?) {
        selection = id
        if let time { focus = (id, time, UUID()) }
    }

    /// Marks which speaker is the user (-1 = none of them, nil = ask again).
    func setMe(_ speaker: Int?, in id: Transcript.ID) {
        update(id, persist: true) { $0.meSpeaker = speaker }
    }

    /// Moves everything `speaker` said to `target` (e.g. two detected voices are one person).
    func mergeSpeaker(_ speaker: Int, into target: Int, in id: Transcript.ID) {
        update(id, persist: true) { transcript in
            transcript.segments = transcript.segments.map { segment in
                var segment = segment
                if segment.speaker == speaker { segment.speaker = target }
                return segment
            }
            transcript.speakerNames[speaker] = nil
        }
        showToast("Speakers merged")
    }

    /// Reassigns specific segments, e.g. one paragraph that was attributed to the wrong person.
    /// Pass nil to create a new speaker.
    func assignSpeaker(_ speaker: Int?, to segmentIDs: [Segment.ID], in id: Transcript.ID) {
        update(id, persist: true) { transcript in
            let target = speaker ?? ((transcript.speakers.max() ?? 0) + 1)
            let ids = Set(segmentIDs)
            transcript.segments = transcript.segments.map { segment in
                var segment = segment
                if ids.contains(segment.id) { segment.speaker = target }
                return segment
            }
        }
    }

    func delete(_ id: Transcript.ID) {
        guard let transcript = transcript(id) else { return }
        do {
            try store.delete(transcript)
        } catch {
            show(error)
            return
        }
        let index = filteredTranscripts.firstIndex { $0.id == id }
        transcripts.removeAll { $0.id == id }
        if transcribingID == id {
            queueTask?.cancel()
            queueTask = nil
            transcribingID = nil
            processQueue()
        }
        if selection == id {
            let remaining = filteredTranscripts
            selection = index.flatMap { remaining.indices.contains($0) ? remaining[$0].id : remaining.last?.id }
        }
    }

    func revealInFinder(_ id: Transcript.ID) {
        guard let transcript = transcript(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: transcript)])
    }

    func copyText(of id: Transcript.ID) {
        guard let transcript = transcript(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptFormatter.plainText(transcript), forType: .string)
        showToast("Copied")
    }

    // MARK: - Feedback

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    func show(_ error: Error) {
        let recordingError = error as? RecordingError
        alert = Alert(message: error.localizedDescription, settingsURL: recordingError?.settingsURL)
    }

    func show(message: String) {
        alert = Alert(message: message)
    }

    // MARK: - Helpers

    func update(_ id: Transcript.ID, persist: Bool, _ change: (inout Transcript) -> Void) {
        guard let index = transcripts.firstIndex(where: { $0.id == id }) else { return }
        var updated = transcripts[index]
        change(&updated)
        transcripts[index] = updated
        guard persist else { return }
        do {
            try store.save(updated)
        } catch {
            show(error)
        }
    }

    func duration(of transcript: Transcript) async -> TimeInterval {
        var longest: TimeInterval = 0
        for track in transcript.tracks {
            let length = (try? await AudioDecoder.duration(of: store.audioURL(for: transcript, track: track))) ?? 0
            longest = max(longest, track.offset + length)
        }
        return longest
    }
}
