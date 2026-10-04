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
                    // Numbers changed, so links to people no longer point at the right voices.
                    $0.speakerPeople = $0.speakerPeople.filter { $0.key == SpeakerID.me }
                    $0.speakerVoiceprints = [:]
                    if $0.meSpeaker != SpeakerID.me { $0.meSpeaker = nil }
                }
                // Known people are found again by their voice.
                await learnVoices(of: id, recognize: true)
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
        activityStarted[id] = Date()
        defer { activity[id] = nil; activityStarted[id] = nil }
        do {
            try await engine.prepare(onProgress: { [weak self] in self?.reportPreparation($0) })
            // A recording cut off by a force quit or crash is rebuilt from its live copy.
            var repaired = false
            for track in transcript.tracks {
                repaired = try await TrackRepair.repairIfNeeded(store.audioURL(for: transcript, track: track)) || repaired
            }
            if repaired || transcript.duration == 0 {
                let length = await duration(of: transcript)
                update(id, persist: true) { $0.duration = length }
            }
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
    func runPipeline(for transcript: Transcript, sources: [(AudioTrack, AudioSource)], isLive: Bool,
                     engine overrideEngine: (any SpeechEngine)? = nil, quality overrideQuality: TranscriptionQuality? = nil,
                     showsProgress: Bool = true) async throws {
        let engine = overrideEngine ?? self.engine
        let quality = overrideQuality ?? settings.quality
        let id = transcript.id
        let progress = PipelineProgress(trackCount: sources.count)
        let planner: WindowPlanner = isLive ? .live : .file

        let results = try await withThrowingTaskGroup(of: (Int, TrackTranscriber.Result).self) { group in
            for (index, (track, source)) in sources.enumerated() {
                let checkpoint = isLive || !showsProgress ? nil : store.loadCheckpoint(for: transcript, track: track)
                // Every track, the microphone included: more than one person can be in the room.
                let diarization = try? await diarizer.makeStream()
                let transcriber = TrackTranscriber(source: source, engine: engine, diarization: diarization, planner: planner,
                                                   shouldPause: { ResourceGovernor.currentPauseReason() })
                // Background priority: the user's apps always come first.
                group.addTask(priority: .utility) {
                    let result = try await transcriber.run(
                        resume: checkpoint?.segments ?? [],
                        resumeUntil: checkpoint?.committedUntil ?? 0
                    ) { [weak self] update in
                        guard showsProgress else { return }
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
        let offsets = sources.map { pair in current.tracks.first { $0.fileName == pair.0.fileName }?.offset ?? pair.0.offset }
        let withCall = sources.contains { $0.0.source == .system }
        var labeled = sources.indices.map {
            Self.label(results[$0]!.segments, track: sources[$0].0, turns: results[$0]!.turns, withCall: withCall)
        }
        if let mic = sources.firstIndex(where: { $0.0.source == .microphone }),
           let system = sources.firstIndex(where: { $0.0.source == .system }) {
            labeled[mic] = await removeSpeakerBleed(mic: labeled[mic], micSource: sources[mic].1, micOffset: offsets[mic],
                                                   system: labeled[system], systemSource: sources[system].1, systemOffset: offsets[system])
        }
        let tracks = sources.indices.map { index in
            TrackMerger.Track(source: sources[index].0.source, offset: offsets[index], segments: labeled[index])
        }
        // Overlapping turns are split where the other person cut in, so the thread reads in order.
        let segments = Interleaver.interleave(TrackMerger.merge(tracks))
        let language = TranscriptionEngine.dominantLanguage(
            weights: results.values.map(\.languageWeights).reduce([:], TranscriptionEngine.merge)
        )
        update(id, persist: true) {
            $0.segments = segments
            $0.language = language ?? $0.language // final, text-weighted choice replaces live guesses
            $0.status = .done
            $0.quality = quality
            if $0.title.hasPrefix(TitleGenerator.recordingPrefix), let suggestion = TitleGenerator.suggestedTitle(from: segments) {
                $0.title = suggestion
            }
        }
        store.clearCheckpoints(for: current)
        if showsProgress, pendingFollowUp != nil, isLive || liveRecordingID == nil { applyPendingFollowUp(to: id) }
        // Learn who sounds like whom, and recognize people the app already knows.
        Task(priority: .utility) { await learnVoices(of: id, recognize: showsProgress) }
    }

    private func pipelineDidUpdate(id: Transcript.ID, track: AudioTrack, index: Int, update progressUpdate: TrackTranscriber.Progress,
                                   progress: PipelineProgress, isLive: Bool) {
        guard let transcript = self.transcript(id) else { return }
        let labeled = Self.label(progressUpdate.committed + progressUpdate.pending, track: track, turns: progressUpdate.turns,
                                 withCall: transcript.tracks.contains { $0.source == .system })
        progress.tracks[index] = TrackMerger.Track(source: track.source, offset: track.offset, segments: labeled)
        // Count text still being decoded too: a whole file can be a single window, and progress
        // must move while it's being worked on, not jump from 0 to 100.
        let reached = max(progressUpdate.committedUntil, progressUpdate.pending.last?.end ?? 0)
        progress.fraction[index] = progressUpdate.availableDuration > 0
            ? min(1, max(progress.fraction[index], reached / progressUpdate.availableDuration)) : 0
        update(id, persist: false) {
            $0.segments = TrackMerger.merge(progress.tracks.compactMap { $0 })
            $0.language = $0.language ?? progressUpdate.language
        }
        if let reason = progressUpdate.pausedReason {
            activity[id] = .paused(reason)
        } else {
            activity[id] = isLive ? .live : .transcribing(progress.overall)
        }
        if progressUpdate.pending.isEmpty, transcript.status == .transcribing {
            try? store.saveCheckpoint(
                TrackCheckpoint(committedUntil: progressUpdate.committedUntil, segments: progressUpdate.committed,
                                language: progressUpdate.language),
                for: transcript, track: track
            )
        }
    }

    /// Drops microphone lines that are only the call coming out of the speakers: their loudness
    /// follows the system channel. Lines where you really spoke over the call are kept.
    private func removeSpeakerBleed(mic: [RawSegment], micSource: AudioSource, micOffset: TimeInterval,
                                    system: [RawSegment], systemSource: AudioSource, systemOffset: TimeInterval) async -> [RawSegment] {
        var kept: [RawSegment] = []
        for segment in mic {
            let start = segment.start + micOffset, end = segment.end + micOffset
            let overlapsCall = system.contains { $0.start + systemOffset < end && start < $0.end + systemOffset }
            if overlapsCall,
               let micAudio = try? await micSource.read(from: segment.start, to: segment.end),
               let callAudio = try? await systemSource.read(from: start - systemOffset, to: end - systemOffset),
               EchoDetector.isBleed(mic: micAudio, system: callAudio) {
                continue
            }
            kept.append(segment)
        }
        return kept
    }

    /// On the microphone, the main voice is "Me" and anyone else in the room keeps their own
    /// label; the call side and imported files use speaker detection as is.
    static func label(_ segments: [RawSegment], track: AudioTrack, turns: [SpeakerTurn], withCall: Bool) -> [RawSegment] {
        guard track.source == .microphone else { return SpeakerAssigner.assign(segments, turns: turns) }
        return withCall ? MicSpeakers.labelWithCall(segments, turns: turns) : MicSpeakers.labelAlone(segments, turns: turns)
    }

    private func relabelSpeakers(in transcript: Transcript, speakerCount: Int?) async throws -> [Segment] {
        var turns: [SpeakerTurn] = []
        let withCall = transcript.tracks.contains { $0.source == .system }
        // With a call, the count applies to the call side; the mic's voices stay as they are.
        // A mic-only recording is an in-person conversation: its voices are what's being counted.
        for track in transcript.tracks where !(withCall && track.source == .microphone) {
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
        let mine = withCall ? transcript.segments.filter { SpeakerID.isOnMicrophone($0.speaker) } : []
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
