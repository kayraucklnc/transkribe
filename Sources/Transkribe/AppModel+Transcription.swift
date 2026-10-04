import Foundation
import TranskribeCore

extension AppModel {
    /// Share of the progress bar spent on transcription; speaker detection gets the rest.
    private static let transcriptionShare = 0.9

    func retry(_ id: Transcript.ID) {
        guard case .failed = transcript(id)?.status else { return }
        update(id, persist: true) { $0.status = .pending }
        processQueue()
    }

    /// Throws away the transcript text and runs the whole pipeline again.
    func transcribeAgain(_ id: Transcript.ID) {
        guard let transcript = transcript(id), transcript.status != .transcribing, transcribingID != id else { return }
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
                try await engine.prepare(onProgress: reportPreparation)
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
        update(id, persist: false) { $0.status = .transcribing; $0.segments = [] }
        activity[id] = .transcribing(0)
        defer { activity[id] = nil }

        do {
            try await engine.prepare(onProgress: reportPreparation)
            var finished: [TrackMerger.Track] = []
            for (index, track) in transcript.tracks.enumerated() {
                let done = finished
                let samples = try await AudioDecoder.decode(url: store.audioURL(for: transcript, track: track))
                let output = try await engine.transcribe(samples: samples) { [weak self] partial in
                    Task { @MainActor in
                        self?.showPartial(id: id, finished: done, current: track, trackIndex: index,
                                          partial: partial, transcript: transcript)
                    }
                }
                update(id, persist: false) { $0.language = $0.language ?? output.language }
                activity[id] = .identifyingSpeakers
                let labeled = try await labelSpeakers(output.segments, track: track, samples: samples)
                finished.append(.init(source: track.source, offset: track.offset, segments: labeled))
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

    /// The microphone in a Mic + System recording is always "Me"; anything else goes
    /// through speaker detection. Detection failures leave the transcript unlabeled.
    private func labelSpeakers(_ segments: [RawSegment], track: AudioTrack, samples: [Float]) async throws -> [RawSegment] {
        if track.source == .microphone {
            return segments.map { var segment = $0; segment.speaker = SpeakerID.me; return segment }
        }
        do {
            return SpeakerAssigner.assign(segments, turns: try await diarizer.turns(samples: samples))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return segments
        }
    }

    private func relabelSpeakers(in transcript: Transcript, speakerCount: Int?) async throws -> [Segment] {
        var turns: [SpeakerTurn] = []
        for track in transcript.tracks where track.source != .microphone {
            let samples = try await AudioDecoder.decode(url: store.audioURL(for: transcript, track: track))
            let found = try await diarizer.turns(samples: samples, speakerCount: speakerCount)
            turns += found.map { SpeakerTurn(start: $0.start + track.offset, end: $0.end + track.offset, speaker: $0.speaker) }
        }
        guard !turns.isEmpty else { return transcript.segments }
        let mine = transcript.segments.filter { $0.speaker == SpeakerID.me }
        let others = transcript.segments
            .filter { $0.speaker != SpeakerID.me }
            .map { RawSegment(start: $0.start, end: $0.end, text: $0.text, words: $0.words) }
        let relabeled = SpeakerAssigner.assign(others, turns: turns).map {
            Segment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker, words: $0.words)
        }
        return (mine + relabeled).sorted { $0.start < $1.start }
    }

    private func showPartial(id: Transcript.ID, finished: [TrackMerger.Track], current: AudioTrack, trackIndex: Int,
                             partial: [RawSegment], transcript: Transcript) {
        guard self.transcript(id)?.status == .transcribing else { return }
        let speaker = current.source == .microphone ? SpeakerID.me : nil
        let labeled = partial.map { var segment = $0; segment.speaker = speaker; return segment }
        let tracks = finished + [.init(source: current.source, offset: current.offset, segments: labeled)]
        update(id, persist: false) { $0.segments = TrackMerger.merge(tracks) }
        let trackProgress = transcript.duration > 0 ? min(1, (partial.last?.end ?? 0) / transcript.duration) : 0
        let overall = (Double(trackIndex) + trackProgress * Self.transcriptionShare) / Double(max(1, transcript.tracks.count))
        activity[id] = .transcribing(overall)
    }

    nonisolated func reportPreparation(_ state: TranscriptionEngine.Preparation) {
        Task { @MainActor in self.modelPreparation = state }
    }
}
