import Foundation

/// A segment as produced by the speech model, relative to the start of its own track.
public struct RawSegment: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var words: [Word]
    public var speaker: Int?

    public init(start: TimeInterval, end: TimeInterval, text: String, words: [Word] = [], speaker: Int? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.words = words
        self.speaker = speaker
    }
}

/// A stretch of audio where one speaker is talking, from speaker detection.
public struct SpeakerTurn: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var speaker: Int

    public init(start: TimeInterval, end: TimeInterval, speaker: Int) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}
