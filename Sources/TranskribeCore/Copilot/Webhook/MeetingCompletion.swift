import Foundation

public enum MeetingCompletion {
    /// Wait for transcription and recovery before sending the meeting end notification.
    @MainActor
    public static func finish(transcription: Task<Void, Error>, recover: (Error) -> Void,
                              sendEnded: () -> Void) async {
        do {
            try await transcription.value
        } catch {
            recover(error)
        }
        sendEnded()
    }

    /// Cancel transcription and finalize at once, without waiting for the cancelled task to end.
    @MainActor
    public static func abandon(transcription: Task<Void, Error>?, finalize: () async -> Void) async {
        transcription?.cancel()
        await finalize()
    }
}
