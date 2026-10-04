import Foundation

/// Combines per-track transcription output into one clean, time-ordered transcript.
public enum TrackMerger {
    public struct Track: Sendable {
        public var source: TrackSource?
        public var offset: TimeInterval
        /// Segments with speakers already assigned.
        public var segments: [RawSegment]

        public init(source: TrackSource?, offset: TimeInterval, segments: [RawSegment]) {
            self.source = source
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
        let shifted = tracks.enumerated().map { trackIndex, track in
            (source: track.source, segments: track.segments.compactMap { raw -> Segment? in
                let words = RepetitionFilter.clean(words: raw.words)
                let text = words.isEmpty ? clean(raw.text) : clean(words.map(\.text).joined())
                guard !text.isEmpty else { return nil }
                return Segment(
                    id: stableID(track: trackIndex, start: raw.start),
                    start: raw.start + track.offset,
                    end: raw.end + track.offset,
                    text: text,
                    speaker: raw.speaker,
                    words: words.map { Word(start: $0.start + track.offset, end: $0.end + track.offset, text: $0.text) }
                )
            })
        }
        let system = shifted.filter { $0.source == .system }.flatMap(\.segments)
        return shifted
            .flatMap { track in
                track.source == .microphone
                    ? track.segments.filter { mic in !system.contains { isEcho(mic, of: $0) } }
                    : track.segments
            }
            .sorted { $0.start < $1.start }
    }

    /// Same input, same ID, so views keep their identity while partial results stream in.
    /// Keyed on where a segment starts, not where it ends: while text streams in, a segment
    /// keeps growing, and its bubble must stay the same view (no flicker, no scroll jump).
    static func stableID(track: Int, start: TimeInterval) -> UUID {
        var hash: (UInt64, UInt64) = (0xcbf29ce484222325, 0x84222325cbf29ce4)
        for value in [UInt64(track), UInt64(bitPattern: Int64(start * 1000))] {
            for shift in stride(from: 0, to: 64, by: 8) {
                let byte = (value >> UInt64(shift)) & 0xff
                hash.0 = (hash.0 ^ byte) &* 0x100000001b3
                hash.1 = (hash.1 ^ byte) &* 0x1000193
            }
        }
        let bytes = withUnsafeBytes(of: (hash.0.bigEndian, hash.1.bigEndian)) { Array($0) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
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
        RepetitionFilter.collapse(text)
            .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[\[\(][^\]\)]*[\]\)]\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(^|\s)[-–—]+\s*(?=\S)"#, with: "$1", options: .regularExpression)
            // Leading "..." Whisper uses for unclear audio.
            .replacingOccurrences(of: #"^(\s*(\.{2,}|…))+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfNoWords ?? ""
    }
}

private extension String {
    /// Text with no letters or digits ("... ...", "—") isn't speech.
    var nilIfNoWords: String? {
        unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) ? self : nil
    }
}
