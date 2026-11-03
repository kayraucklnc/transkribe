import Foundation

/// A progress snapshot for one audio track. All times are relative to the track start.
public struct LiveTrackProgress: Sendable {
    /// Final segments.
    public var committed: [RawSegment]
    /// Segments from the current window that are not final.
    public var pending: [RawSegment]
    /// The time through which transcription is complete.
    public var committedUntil: TimeInterval
    public var availableDuration: TimeInterval
    public var turns: [SpeakerTurn]
    public var language: String?
    public var pausedReason: String?

    public init(
        committed: [RawSegment],
        pending: [RawSegment],
        committedUntil: TimeInterval,
        availableDuration: TimeInterval,
        turns: [SpeakerTurn],
        language: String?,
        pausedReason: String? = nil
    ) {
        self.committed = committed
        self.pending = pending
        self.committedUntil = committedUntil
        self.availableDuration = availableDuration
        self.turns = turns
        self.language = language
        self.pausedReason = pausedReason
    }
}
