import Foundation

/// A segment as produced by the speech model, relative to the start of its own track.
public struct RawSegment: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Combines per-track transcription output into one clean, time-ordered transcript.
public enum TrackMerger {
    public struct Track: Sendable {
        public var speaker: Speaker?
        public var offset: TimeInterval
        public var segments: [RawSegment]

        public init(speaker: Speaker?, offset: TimeInterval, segments: [RawSegment]) {
            self.speaker = speaker
            self.offset = offset
            self.segments = segments
        }
    }

    /// Mic segments this similar to an overlapping system-audio segment are treated as
    /// speaker bleed (the mic hearing the call through the speakers) and dropped.
    static let echoSimilarityThreshold = 0.6
    /// Short replies ("okay", "yes") are too ambiguous to call echo.
    static let echoMinimumWords = 4

    public static func merge(_ tracks: [Track]) -> [Segment] {
        let labelSpeakers = tracks.count > 1
        let shifted = tracks.flatMap { track in
            track.segments.compactMap { raw -> Segment? in
                let text = clean(raw.text)
                guard !text.isEmpty else { return nil }
                return Segment(
                    start: raw.start + track.offset,
                    end: raw.end + track.offset,
                    text: text,
                    speaker: labelSpeakers ? track.speaker : nil
                )
            }
        }
        let others = shifted.filter { $0.speaker == .others }
        return shifted
            .filter { segment in
                segment.speaker != .me || !others.contains { isEcho(segment, of: $0) }
            }
            .sorted { $0.start < $1.start }
    }

    /// Jaccard similarity of the word sets, ignoring case and punctuation.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let wordsA = words(a), wordsB = words(b)
        let union = wordsA.union(wordsB)
        guard !union.isEmpty else { return 0 }
        return Double(wordsA.intersection(wordsB).count) / Double(union.count)
    }

    // MARK: - Helpers

    private static func isEcho(_ mic: Segment, of system: Segment) -> Bool {
        let overlaps = mic.start < system.end && system.start < mic.end
        return overlaps && words(mic.text).count >= echoMinimumWords && similarity(mic.text, system.text) >= echoSimilarityThreshold
    }

    private static func words(_ text: String) -> Set<String> {
        Set(
            TranscriptSearch.normalize(text)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    /// Strips Whisper special tokens (`<|en|>`), non-speech markers (`[BLANK_AUDIO]`, `(music)`)
    /// and the subtitle-style dialogue dash Whisper puts in front of some lines.
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[\[\(][^\]\)]*[\]\)]\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-–—]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
