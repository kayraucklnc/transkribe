import Foundation
import TranskribeCore

extension AppModel {
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
        selectedPerson = nil
        startFailure = nil
        selection = nil
        levels = Array(repeating: 0, count: Self.levelHistory)
        let source = recordingSource
        let transcript = Transcript(title: TitleGenerator.recordingTitle(), tracks: [])
        let recorder = RecordingSession(source: source, directory: store.directory(for: transcript))
        Task {
            do {
                try await RecordingSession.requestPermissions(for: source)
                try await recorder.start(
                    onLevel: { [weak self] level in
                        Task { @MainActor in self?.pushLevel(level) }
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
                startLiveTranscription(of: transcript, recorder: recorder)
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
                levels = Array(repeating: 0, count: Self.levelHistory)
            }
            let id = draft.id
            do {
                let tracks = try await recorder.stop()
                var finished = transcript(id) ?? draft
                finished.tracks = tracks
                finished.duration = await duration(of: finished)
                update(id, persist: true) {
                    $0.tracks = finished.tracks
                    $0.duration = finished.duration
                }
                live?.sources.forEach { $0.markComplete() }
                if let task = live?.task {
                    // The last batch is transcribed from the live copy; then the transcript is final.
                    live = nil
                    await finishLiveTranscription(id: id, task: task)
                } else {
                    update(id, persist: true) { $0.status = .pending }
                    processQueue()
                }
            } catch RecordingError.nothingRecorded {
                live?.task.cancel()
                live = nil
                if let transcript = transcript(id) { delete(transcript.id) } else { try? store.delete(draft) }
                show(RecordingError.nothingRecorded)
            } catch {
                live?.task.cancel()
                live = nil
                // Keep the audio: it is transcribed again from the saved files.
                update(id, persist: true) { $0.status = .pending }
                show(error)
            }
        }
    }

    // MARK: - Live transcription

    /// Shows the recording as a transcript right away and transcribes it in batches while it runs.
    private func startLiveTranscription(of draft: Transcript, recorder: RecordingSession) {
        var transcript = draft
        transcript.status = .transcribing
        transcript.tracks = recorder.liveTracks.map { track in
            AudioTrack(fileName: track.source == .microphone ? RecordingSession.microphoneFile : RecordingSession.systemFile,
                       source: track.source)
        }
        try? store.save(transcript)
        transcripts.insert(transcript, at: 0)
        liveRecordingID = transcript.id

        let sources = recorder.liveTracks.map { LiveAudioSource(url: $0.url) }
        let pairs = zip(transcript.tracks, sources).map { ($0, $1 as AudioSource) }
        let task = Task { [weak self] in
            guard let self else { return }
            try await self.runPipeline(for: transcript, sources: pairs, isLive: true)
        }
        live = (task, sources)
        activity[transcript.id] = .live
    }

    private func finishLiveTranscription(id: Transcript.ID, task: Task<Void, Error>) async {
        do {
            try await task.value
        } catch {
            // Fall back to transcribing the finished recording files from scratch.
            update(id, persist: true) { $0.status = .pending; $0.segments = [] }
            processQueue()
        }
        activity[id] = nil
        liveRecordingID = nil
        selection = id
    }

    /// Called on quit: finalizes an in-progress recording so its audio isn't lost.
    func finishRecordingForTermination() async {
        guard case .recording = recordingState, let (recorder, draft) = session else { return }
        session = nil
        recordingState = .stopping
        live?.task.cancel()
        live = nil
        var transcript = self.transcript(draft.id) ?? draft
        if let tracks = try? await recorder.stop() {
            transcript.tracks = tracks
            transcript.duration = await duration(of: transcript)
            // Picked up again on next launch; checkpoints let it continue where it stopped.
            transcript.status = .pending
            try? store.save(transcript)
        }
        recordingState = .idle
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

    private func pushLevel(_ level: Float) {
        guard case .recording = recordingState else { return }
        levels.removeFirst()
        levels.append(level)
    }
}
