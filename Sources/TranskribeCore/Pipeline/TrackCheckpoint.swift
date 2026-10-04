import Foundation

/// How far a track's transcription has come: the committed segments and where to continue.
public struct TrackCheckpoint: Codable, Equatable, Sendable {
    public var committedUntil: TimeInterval
    public var segments: [RawSegment]
    public var language: String?

    public init(committedUntil: TimeInterval, segments: [RawSegment], language: String?) {
        self.committedUntil = committedUntil
        self.segments = segments
        self.language = language
    }
}
