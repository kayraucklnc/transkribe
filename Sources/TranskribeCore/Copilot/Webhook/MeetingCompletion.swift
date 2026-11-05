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
}
