import Foundation
import TranskribeCore

extension AppModel {
    func retry(_ id: Transcript.ID) {
        guard case .failed = transcript(id)?.status else { return }
        update(id, persist: true) { $0.status = .pending }
        processQueue()
    }

    /// Throws away the transcript text and runs the whole pipeline again.
    func transcribeAgain(_ id: Transcript.ID) {
        guard let transcript = transcript(id), transcript.status != .transcribing, transcribingID != id else { return }
        store.clearCheckpoints(for: transcript)
        update(id, persist: true) {
            $0.status = .pending
            $0.segments = []
        }
        processQueue()
    }

    /// Re-runs speaker detection with a known number of speakers (nil = automatic).
    func setSpeakerCount(_ count: Int?, for id: Transcript.ID) {
        guard let transcript = transcript(id), transcript.status == .done, activity[id] == nil else { return }
        activity[id] = .identifyingSpeakers
        Task {
            defer { activity[id] = nil }
            do {
                let segments = try await relabelSpeakers(in: transcript, speakerCount: count)
                update(id, persist: true) {
                    $0.segments = segments
                    $0.speakerNames = $0.speakerNames.filter { $0.key == SpeakerID.me }
                    if $0.meSpeaker != SpeakerID.me { $0.meSpeaker = nil }
                }
            } catch {
                show(message: "Couldn't identify speakers. \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Queue

    func preloadModel() {
        Task {
            do {
                try await engine.prepare(onProgress: { [weak self] in self?.reportPreparation($0) })
            } catch {
                modelPreparation = nil
            }
        }
    }

    /// Transcribes pending items one at a time, oldest first.
    func processQueue() {
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
        update(id, persist: false) { $0.status = .transcribing }
        activity[id] = .transcribing(0)
        defer { activity[id] = nil }
        do {
            try await engine.prepare(onProgress: { [weak self] in self?.reportPreparation($0) })
            let sources = transcript.tracks.map { track in
                (track, FileAudioSource(url: store.audioURL(for: transcript, track: track)) as AudioSource)
            }
            try await runPipeline(for: transcript, sources: sources, isLive: false)
        } catch is CancellationError {
            update(id, persist: true) { $0.status = .pending }
        } catch {
            update(id, persist: true) { $0.status = .failed(error.localizedDescription) }
            if case .ready = modelPreparation {} else { modelPreparation = nil }
        }
    }

    // MARK: - Pipeline

    /// Transcribes every track in windows (all tracks progress together, which matters while a
    /// recording is still running), shows results as they are committed, saves checkpoints, and
    /// finishes with speaker labels and a merged transcript.
    func runPipeline(for transcript: Transcript, sources: [(AudioTrack, AudioSource)], isLive: Bool) async throws {
        let id = transcript.id
        let progress = PipelineProgress(trackCount: sources.count)
        let planner: WindowPlanner = isLive ? .live : .file

        let results = try await withThrowingTaskGroup(of: (Int, TrackTranscriber.Result).self) { group in
            for (index, (track, source)) in sources.enumerated() {
                let checkpoint = isLive ? nil : store.loadCheckpoint(for: transcript, track: track)
                let diarization = track.source == .microphone ? nil : try? await diarizer.makeStream()
                let transcriber = TrackTranscriber(source: source, engine: engine, diarization: diarization, planner: planner)
                group.addTask {
                    let result = try await transcriber.run(
                        resume: checkpoint?.segments ?? [],
                        resumeUntil: checkpoint?.committedUntil ?? 0
                    ) { [weak self] update in
                        await self?.pipelineDidUpdate(id: id, track: track, index: index, update: update,
                                                      progress: progress, isLive: isLive)
                    }
                    return (index, result)
                }
            }
            var results: [Int: TrackTranscriber.Result] = [:]
            for try await (index, result) in group { results[index] = result }
            return results
        }

        guard let current = self.transcript(id) else { return }
        let tracks = sources.enumerated().map { index, pair in
            let (track, _) = pair
            let result = results[index]!
            return TrackMerger.Track(source: track.source, offset: current.tracks.first { $0.fileName == track.fileName }?.offset ?? track.offset,
                                     segments: Self.label(result.segments, track: track, turns: result.turns))
        }
        let segments = TrackMerger.merge(tracks)
        let language = TranscriptionEngine.dominantLanguage(results.values.compactMap(\.language))
        update(id, persist: true) {
            $0.segments = segments
            $0.language = language ?? $0.language
            $0.status = .done
            if $0.title.hasPrefix(TitleGenerator.recordingPrefix), let suggestion = TitleGenerator.suggestedTitle(from: segments) {
                $0.title = suggestion
            }
        }
        store.clearCheckpoints(for: current)
    }

    private func pipelineDidUpdate(id: Transcript.ID, track: AudioTrack, index: Int, update progressUpdate: TrackTranscriber.Progress,
                                   progress: PipelineProgress, isLive: Bool) {
        guard let transcript = self.transcript(id) else { return }
        let labeled = Self.label(progressUpdate.committed + progressUpdate.pending, track: track, turns: progressUpdate.turns)
        progress.tracks[index] = TrackMerger.Track(source: track.source, offset: track.offset, segments: labeled)
        progress.fraction[index] = progressUpdate.availableDuration > 0
            ? min(1, progressUpdate.committedUntil / progressUpdate.availableDuration) : 0
        update(id, persist: false) {
            $0.segments = TrackMerger.merge(progress.tracks.compactMap { $0 })
            $0.language = $0.language ?? progressUpdate.language
        }
        activity[id] = isLive ? .live : .transcribing(progress.overall)
        if progressUpdate.pending.isEmpty {
            try? store.saveCheckpoint(
                TrackCheckpoint(committedUntil: progressUpdate.committedUntil, segments: progressUpdate.committed,
                                language: progressUpdate.language),
                for: transcript, track: track
            )
        }
    }

    /// The microphone in a Mic + System recording is always "Me"; other tracks use speaker detection.
    static func label(_ segments: [RawSegment], track: AudioTrack, turns: [SpeakerTurn]) -> [RawSegment] {
        if track.source == .microphone {
            return segments.map { var segment = $0; segment.speaker = SpeakerID.me; return segment }
        }
        return SpeakerAssigner.assign(segments, turns: turns)
    }

    private func relabelSpeakers(in transcript: Transcript, speakerCount: Int?) async throws -> [Segment] {
        var turns: [SpeakerTurn] = []
        for track in transcript.tracks where track.source != .microphone {
            let source = FileAudioSource(url: store.audioURL(for: transcript, track: track))
            let stream = try await diarizer.makeStream()
            let duration = try await source.availableDuration()
            for start in stride(from: 0.0, to: duration, by: 300) {
                try stream.append(try await source.read(from: start, to: min(duration, start + 300)))
            }
            try stream.finish()
            turns += stream.turns(speakerCount: speakerCount).map {
                SpeakerTurn(start: $0.start + track.offset, end: $0.end + track.offset, speaker: $0.speaker)
            }
        }
        guard !turns.isEmpty else { return transcript.segments }
        let mine = transcript.segments.filter { $0.speaker == SpeakerID.me && transcript.tracks.contains { $0.source == .microphone } }
        let others = transcript.segments
            .filter { !mine.contains($0) }
            .map { RawSegment(start: $0.start, end: $0.end, text: $0.text, words: $0.words) }
        let relabeled = SpeakerAssigner.assign(others, turns: turns).map {
            Segment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker, words: $0.words)
        }
        return (mine + relabeled).sorted { $0.start < $1.start }
    }

    nonisolated func reportPreparation(_ state: TranscriptionEngine.Preparation) {
        Task { @MainActor in self.modelPreparation = state }
    }
}

/// Per-track state of a running pipeline, owned by the main actor.
@MainActor
final class PipelineProgress {
    var tracks: [TrackMerger.Track?]
    var fraction: [Double]

    init(trackCount: Int) {
        tracks = Array(repeating: nil, count: trackCount)
        fraction = Array(repeating: 0, count: trackCount)
    }

    var overall: Double {
        fraction.isEmpty ? 0 : fraction.reduce(0, +) / Double(fraction.count)
    }
}
