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
            insert(transcript)
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
