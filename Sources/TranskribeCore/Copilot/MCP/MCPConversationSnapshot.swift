import Foundation

/// A current transcript and its recording lifecycle. Include pending text in the transcript.
public struct MCPConversationSnapshot: Sendable {
    public var transcript: Transcript
    public var isLive: Bool
    public var endedAt: Date?

    public init(transcript: Transcript, isLive: Bool, endedAt: Date? = nil) {
        self.transcript = transcript
        self.isLive = isLive
        self.endedAt = endedAt
    }
}
