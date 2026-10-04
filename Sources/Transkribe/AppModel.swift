import AppKit
import Observation
import UniformTypeIdentifiers
import TranskribeCore

@MainActor
@Observable
final class AppModel {
    enum RecordingState: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case stopping
    }

    struct Alert: Identifiable {
        let id = UUID()
        var message: String
        var settingsURL: URL?
    }

    private(set) var transcripts: [Transcript] = []
    var selection: Transcript.ID?
    var query = ""
    var alert: Alert?

    private(set) var modelPreparation: TranscriptionEngine.Preparation?
    private(set) var progress: [Transcript.ID: Double] = [:]

    private(set) var recordingState: RecordingState = .idle
    private(set) var level: Float = 0
    var recordingSource: RecordingSource {
        didSet { UserDefaults.standard.set(recordingSource.rawValue, forKey: Self.sourceKey) }
    }

    let store: TranscriptStore
    private let engine: TranscriptionEngine
    private var session: (recorder: RecordingSession, transcript: Transcript)?
    private var startFailure: Error?
    private var queueTask: Task<Void, Never>?
    private var transcribingID: Transcript.ID?
    private static let sourceKey = "recordingSource"

    init(store: TranscriptStore = TranscriptStore(rootDirectory: TranscriptStore.defaultRoot),
         engine: TranscriptionEngine = TranscriptionEngine()) {
        self.store = store
        self.engine = engine
        recordingSource = UserDefaults.standard.string(forKey: Self.sourceKey).flatMap(RecordingSource.init) ?? .microphone
        do {
            _ = try store.recoverInterruptedRecordings()
            transcripts = try store.loadAll()
        } catch {
            show(error)
        }
        FileImport.removeTemporaryCopies()
        processQueue()
        preloadModel()
    }

    // MARK: - Queries

    var filteredTranscripts: [Transcript] {
        transcripts.filter { TranscriptSearch.matches($0, query: query) }
    }

    var selectedTranscript: Transcript? {
        transcripts.first { $0.id == selection }
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
        let fileName = isVideo || url.pathExtension.isEmpty ? "audio.m4a" : "audio.\(url.pathExtension.lowercased())"
        var transcript = Transcript(title: TitleGenerator.title(forFile: url), tracks: [AudioTrack(fileName: fileName)])
        let destination = store.audioURL(for: transcript, track: transcript.tracks[0])
        do {
            try store.prepareDirectory(for: transcript)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if isVideo || url.pathExtension.isEmpty {
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
        transcripts.insert(transcript, at: 0)
        selection = transcript.id
        processQueue()
    }

    // MARK: - Recording

    func toggleRecording() {
        switch recordingState {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .starting, .stopping: break
        }
    }

    func startRecording() {
        guard recordingState == .idle else { return }
        recordingState = .starting
        startFailure = nil
        let source = recordingSource
        let transcript = Transcript(title: TitleGenerator.recordingTitle(), tracks: [])
        let recorder = RecordingSession(source: source, directory: store.directory(for: transcript))
        Task {
            do {
                try await RecordingSession.requestPermissions(for: source)
                try await recorder.start(
                    onLevel: { [weak self] level in
                        Task { @MainActor in self?.level = level }
                    },
                    onFailure: { [weak self] error in
                        Task { @MainActor in self?.recordingFailed(error) }
                    }
                )
                if let failure = startFailure {
                    _ = try? await recorder.stop()
                    throw failure
                }
                session = (recorder, transcript)
                recordingState = .recording(since: Date())
            } catch {
                try? store.delete(transcript)
                recordingState = .idle
                show(error)
            }
        }
    }

    func stopRecording() {
        guard case .recording = recordingState, let (recorder, draft) = session else { return }
        recordingState = .stopping
        session = nil
        Task {
            defer {
                recordingState = .idle
                level = 0
            }
            var transcript = draft
            do {
                transcript.tracks = try await recorder.stop()
                transcript.duration = await duration(of: transcript)
                try store.save(transcript)
            } catch RecordingError.nothingRecorded {
                try? store.delete(transcript)
                show(RecordingError.nothingRecorded)
                return
            } catch {
                // Keep the audio: it is recovered as a pending transcript on next launch.
                show(error)
                return
            }
            transcripts.insert(transcript, at: 0)
            selection = transcript.id
            processQueue()
        }
    }

    private func recordingFailed(_ error: Error) {
        switch recordingState {
        case .starting: startFailure = error
        case .recording:
            show(error)
            stopRecording()
        case .idle, .stopping: break
        }
    }

    /// Called on quit: finalizes an in-progress recording so its audio isn't lost.
    func finishRecordingForTermination() async {
        guard case .recording = recordingState, let (recorder, draft) = session else { return }
        session = nil
        recordingState = .stopping
        var transcript = draft
        if let tracks = try? await recorder.stop() {
            transcript.tracks = tracks
            transcript.duration = await duration(of: transcript)
            try? store.save(transcript)
        }
        recordingState = .idle
    }

    // MARK: - Editing

    func rename(_ id: Transcript.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id, persist: true) { $0.title = trimmed }
    }

    func delete(_ id: Transcript.ID) {
        guard let transcript = transcripts.first(where: { $0.id == id }) else { return }
        do {
            try store.delete(transcript)
        } catch {
            show(error)
            return
        }
        transcripts.removeAll { $0.id == id }
        if transcribingID == id {
            queueTask?.cancel()
            queueTask = nil
            transcribingID = nil
            processQueue()
        }
        if selection == id { selection = filteredTranscripts.first?.id }
    }

    func retry(_ id: Transcript.ID) {
        guard case .failed = transcripts.first(where: { $0.id == id })?.status else { return }
        update(id, persist: true) { $0.status = .pending }
        processQueue()
    }

    func revealInFinder(_ id: Transcript.ID) {
        guard let transcript = transcripts.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: transcript)])
    }

    func copyText(of id: Transcript.ID) {
        guard let transcript = transcripts.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptFormatter.plainText(transcript), forType: .string)
    }

    // MARK: - Transcription queue

    /// Loads (or downloads) the model at launch so the first drop starts transcribing right away.
    /// Failures here are ignored; they surface on the transcript that needs the model.
    private func preloadModel() {
        Task {
            do {
                try await engine.prepare(onProgress: reportPreparation)
            } catch {
                modelPreparation = nil
            }
        }
    }

    private nonisolated func reportPreparation(_ state: TranscriptionEngine.Preparation) {
        Task { @MainActor in self.modelPreparation = state }
    }

    /// Transcribes pending items one at a time, oldest first.
    private func processQueue() {
        guard queueTask == nil else { return }
        queueTask = Task {
            while !Task.isCancelled, let next = transcripts.last(where: { $0.status == .pending }) {
                transcribingID = next.id
                await transcribe(next)
                transcribingID = nil
            }
            if !Task.isCancelled { queueTask = nil }
        }
    }

    private func transcribe(_ transcript: Transcript) async {
        let id = transcript.id
        update(id, persist: false) { $0.status = .transcribing; $0.segments = [] }
        progress[id] = 0
        defer { progress[id] = nil }

        do {
            try await engine.prepare(onProgress: reportPreparation)
            var finished: [TrackMerger.Track] = []
            for track in transcript.tracks {
                let done = finished
                let samples = try await AudioDecoder.decode(url: store.audioURL(for: transcript, track: track))
                let output = try await engine.transcribe(samples: samples) { [weak self] partial in
                    Task { @MainActor in
                        self?.showPartial(id: id, finished: done, current: track, partial: partial,
                                          trackCount: transcript.tracks.count, duration: transcript.duration)
                    }
                }
                finished.append(.init(speaker: track.speaker, offset: track.offset, segments: output.segments))
                update(id, persist: false) { $0.language = $0.language ?? output.language }
            }
            let segments = TrackMerger.merge(finished)
            update(id, persist: true) {
                $0.segments = segments
                $0.status = .done
                if $0.title.hasPrefix(TitleGenerator.recordingPrefix), let suggestion = TitleGenerator.suggestedTitle(from: segments) {
                    $0.title = suggestion
                }
            }
        } catch is CancellationError {
            update(id, persist: true) { $0.status = .pending }
        } catch {
            update(id, persist: true) { $0.status = .failed(error.localizedDescription) }
            if case .ready = modelPreparation {} else { modelPreparation = nil }
        }
    }

    private func showPartial(id: Transcript.ID, finished: [TrackMerger.Track], current: AudioTrack,
                             partial: [RawSegment], trackCount: Int, duration: TimeInterval) {
        guard transcripts.first(where: { $0.id == id })?.status == .transcribing else { return }
        let tracks = finished + [.init(speaker: current.speaker, offset: current.offset, segments: partial)]
        update(id, persist: false) { $0.segments = TrackMerger.merge(tracks) }
        let trackProgress = duration > 0 ? min(1, (partial.last?.end ?? 0) / duration) : 0
        progress[id] = (Double(finished.count) + trackProgress) / Double(max(1, trackCount))
    }

    // MARK: - Helpers

    private func update(_ id: Transcript.ID, persist: Bool, _ change: (inout Transcript) -> Void) {
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

    private func duration(of transcript: Transcript) async -> TimeInterval {
        var longest: TimeInterval = 0
        for track in transcript.tracks {
            let length = (try? await AudioDecoder.duration(of: store.audioURL(for: transcript, track: track))) ?? 0
            longest = max(longest, track.offset + length)
        }
        return longest
    }

    private func show(_ error: Error) {
        let recordingError = error as? RecordingError
        alert = Alert(message: error.localizedDescription, settingsURL: recordingError?.settingsURL)
    }

    private func show(message: String) {
        alert = Alert(message: message)
    }
}
