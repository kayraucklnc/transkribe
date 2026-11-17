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

    func startRecording(title: String? = nil) {
        guard recordingState == .idle else { return }
        recordingState = .starting
        selectedPerson = nil
        startFailure = nil
        selection = nil
        levels = Array(repeating: 0, count: Self.levelHistory)
        // Live text needs the Mac to keep up: a background pass waits until the recording ends.
        if enhancingID != nil { startEnhancing() }
        let source = recordingSource
        let transcript = Transcript(title: title ?? TitleGenerator.recordingTitle(), tracks: [])
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
                sendWebhook(.meetingStarted, for: transcript)
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
        update(draft.id, persist: true) { $0.recordingEndedAt = Date() }
        session = nil
        Task {
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
                    // That can take minutes when live text fell behind, so the recording is over now:
                    // the rest shows as ordinary transcription progress.
                    live = nil
                    releaseRecording(id)
                    showRemainingTranscription(of: id, startedAt: recorder.startedAt)
                    await finishLiveTranscription(id: id, task: task, startedAt: recorder.startedAt)
                } else {
                    releaseRecording(id)
                    await finishTopicGraph(for: id, startedAt: recorder.startedAt)
                    update(id, persist: true) { $0.status = .pending }
                    processQueue()
                    finishLiveIntents(id: id)
                    sendWebhook(.meetingEnded, for: transcript(id) ?? draft)
                }
            } catch RecordingError.nothingRecorded {
                let task = live?.task
                live = nil
                releaseRecording(id)
                await MeetingCompletion.abandon(transcription: task) {
                    await finishTopicGraph(for: id, startedAt: recorder.startedAt)
                }
                if let transcript = transcript(id) { delete(transcript.id) } else { try? store.delete(draft) }
                show(RecordingError.nothingRecorded)
                if liveIntents?.meetingID == id { liveIntents?.pause() }
                sendWebhook(.meetingEnded, for: draft)
            } catch {
                let task = live?.task
                live = nil
                releaseRecording(id)
                await MeetingCompletion.abandon(transcription: task) {
                    await finishTopicGraph(for: id, startedAt: recorder.startedAt)
                }
                // Keep the audio: it is transcribed again from the saved files.
                update(id, persist: true) { $0.status = .pending }
                show(error)
                if liveIntents?.meetingID == id { liveIntents?.pause() }
                sendWebhook(.meetingEnded, for: transcript(id) ?? draft)
            }
        }
    }

    // MARK: - Live transcription

    /// Shows the recording as a transcript right away and transcribes it in batches while it runs.
    private func startLiveTranscription(of draft: Transcript, recorder: RecordingSession) {
        var transcript = draft
        transcript.recordingEndedAt = nil
        transcript.status = .transcribing
        transcript.tracks = recorder.liveTracks.map { track in
            AudioTrack(fileName: track.source == .microphone ? RecordingSession.microphoneFile : RecordingSession.systemFile,
                       source: track.source)
        }
        try? store.save(transcript)
        transcripts.insert(transcript, at: 0)
        liveRecordingID = transcript.id
        startTopicGraph(for: transcript, startedAt: recorder.startedAt ?? Date())

        let sources = recorder.liveTracks.map { LiveAudioSource(url: $0.url) }
        let pairs = zip(transcript.tracks, sources).map { ($0, $1 as AudioSource) }
        let task = Task { [weak self] in
            guard let self else { return }
            // A model that keeps up with the call, so Stop shows the transcript in seconds.
            try await self.runPipeline(for: transcript, sources: pairs, isLive: true,
                                       engine: self.engineWhileRecording(), quality: self.settings.quality.whileRecording)
        }
        live = (task, sources)
        activity[transcript.id] = .live
    }

    /// The recording is over: the record button is free again and the conversation stops showing
    /// as live, even while its last minutes are still being transcribed.
    private func releaseRecording(_ id: Transcript.ID) {
        recordingState = .idle
        levels = Array(repeating: 0, count: Self.levelHistory)
        if liveRecordingID == id { liveRecordingID = nil }
    }

    /// Shows what live transcription still has to do as a progress card with the time left. The
    /// rate so far (since the recording started) predicts the rest, so the estimate is right away.
    private func showRemainingTranscription(of id: Transcript.ID, startedAt: Date?) {
        guard let transcript = transcript(id) else { return }
        let reached = transcript.segments.map(\.end).max() ?? 0
        activity[id] = .transcribing(transcript.duration > 0 ? min(1, reached / transcript.duration) : 0)
        activityStarted[id] = startedAt ?? Date()
        selection = id
    }

    private func finishLiveTranscription(id: Transcript.ID, task: Task<Void, Error>, startedAt: Date?) async {
        let finalized = Task {
            let result = await task.result
            await finishTopicGraph(for: id, startedAt: startedAt)
            try result.get()
        }
        await MeetingCompletion.finish(transcription: finalized, recover: { _ in
            // Fall back to transcribing the finished recording files from scratch.
            update(id, persist: true) { $0.status = .pending; $0.segments = [] }
            processQueue()
        }, sendEnded: {
            // A new recording may have started meanwhile: only this conversation's state is cleared.
            activity[id] = nil
            activityStarted[id] = nil
            finishLiveIntents(id: id)
            if liveRecordingID == id { liveRecordingID = nil }
            if let transcript = transcript(id) { sendWebhook(.meetingEnded, for: transcript) }
        })
    }

    /// Called on quit: finalizes an in-progress recording so its audio isn't lost.
    func finishRecordingForTermination() async {
        guard case .recording = recordingState, let (recorder, draft) = session else { return }
        session = nil
        recordingState = .stopping
        let task = live?.task
        live = nil
        // Quit must not wait for the cancelled task: it can wait for an import or a model download.
        await MeetingCompletion.abandon(transcription: task) {
            let endedAt = Date()
            let tracks = try? await recorder.stop()
            var transcript = self.transcript(draft.id) ?? draft
            transcript.recordingEndedAt = endedAt
            if let tracks {
                transcript.tracks = tracks
                transcript.duration = await duration(of: transcript)
                // Picked up again on next launch; checkpoints let it continue where it stopped.
                transcript.status = .pending
                try? store.save(transcript)
            }
            await topicGraphs[transcript.id]?.finish(tracks: transcript.tracks, startedAt: recorder.startedAt)
            liveIntents?.pause()
            sendWebhook(.meetingEnded, for: transcript)
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
