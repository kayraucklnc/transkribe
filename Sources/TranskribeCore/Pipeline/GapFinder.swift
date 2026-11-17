import Foundation

/// Speech recognizers occasionally skip a whole sentence. Comparing where the audio has speech
/// with where text came out finds those holes so they can be transcribed on their own.
public enum GapFinder {
    /// Holes shorter than this are pauses inside speech, not lost sentences.
    static let minimumGap: TimeInterval = 1.2
    static let frame = 320 // 20 ms at 16 kHz

    /// Retry clips are joined across pauses shorter than this, so a dropped stretch is redone with
    /// its context instead of as many one-second scraps.
    static let joinWithin: TimeInterval = 2.5
    /// One Whisper window, so a retry clip is decoded in a single pass.
    static let longestRetry: TimeInterval = 28

    /// Speech with no text under it. A line without words (the recognizer gave up on that
    /// stretch) doesn't count as covering anything.
    public static func uncovered(speech: [Range<TimeInterval>], segments: [RawSegment]) -> [Range<TimeInterval>] {
        let covered = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { ($0.start - 0.15)..<($0.end + 0.15) }.sorted { $0.lowerBound < $1.lowerBound }
        var gaps: [Range<TimeInterval>] = []
        for region in speech {
            var cursor = region.lowerBound
            for range in covered where range.upperBound > cursor && range.lowerBound < region.upperBound {
                if range.lowerBound > cursor { gaps.append(cursor..<range.lowerBound) }
                cursor = max(cursor, range.upperBound)
            }
            if cursor < region.upperBound { gaps.append(cursor..<region.upperBound) }
        }
        return gaps.filter { $0.upperBound - $0.lowerBound >= minimumGap }
    }

    /// Stretches to transcribe again: nearby gaps joined into one clip, none longer than one window.
    public static func retrySpans(_ gaps: [Range<TimeInterval>]) -> [Range<TimeInterval>] {
        var spans: [Range<TimeInterval>] = []
        for gap in gaps.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = spans.last, gap.lowerBound - last.upperBound < joinWithin,
               gap.upperBound - last.lowerBound <= longestRetry {
                spans[spans.count - 1] = last.lowerBound..<max(last.upperBound, gap.upperBound)
            } else {
                spans.append(gap)
            }
        }
        // A single gap longer than a window is split into windows.
        return spans.flatMap { span -> [Range<TimeInterval>] in
            stride(from: span.lowerBound, to: span.upperBound, by: longestRetry).map {
                $0..<min(span.upperBound, $0 + longestRetry)
            }
        }
    }

    /// What a recognizer returned for a clip of `duration` seconds, made safe to use: lines without
    /// words are dropped (they'd hide speech from the retry) and times are kept inside the clip
    /// (Whisper's VAD chunking sometimes reports a line past the end of what it was given).
    public static func cleaned(_ segments: [RawSegment], duration: TimeInterval) -> [RawSegment] {
        segments.compactMap { segment in
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  segment.start < duration else { return nil }
            var segment = segment
            segment.start = max(0, segment.start)
            segment.end = min(duration, max(segment.start, segment.end))
            segment.words = segment.words.map { word in
                var word = word
                word.start = min(duration, max(0, word.start))
                word.end = min(duration, max(word.start, word.end))
                return word
            }
            return segment
        }
    }

    /// Stretches of speech, from loudness relative to the recording's own noise floor.
    public static func speechRegions(in samples: [Float], sampleRate: Double = 16_000) -> [Range<TimeInterval>] {
        let energies = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start -> Float in
            var sum: Float = 0
            for index in start..<(start + frame) { sum += samples[index] * samples[index] }
            return (sum / Float(frame)).squareRoot()
        }
        guard !energies.isEmpty else { return [] }
        let sorted = energies.sorted()
        let floor = sorted[sorted.count / 10]
        let threshold = max(floor * 4, 0.01)
        var regions: [Range<TimeInterval>] = []
        var start: Int?
        var silence = 0
        for (index, energy) in energies.enumerated() {
            if energy >= threshold {
                if start == nil { start = index }
                silence = 0
            } else if let open = start {
                silence += 1
                if silence > 15 { // 300 ms of quiet closes a region
                    regions.append(time(open, sampleRate)..<time(index - silence + 1, sampleRate))
                    start = nil
                    silence = 0
                }
            }
        }
        if let open = start { regions.append(time(open, sampleRate)..<time(energies.count - silence, sampleRate)) }
        return regions.filter { $0.upperBound - $0.lowerBound >= 0.3 }
    }

    private static func time(_ frameIndex: Int, _ rate: Double) -> TimeInterval {
        Double(frameIndex * frame) / rate
    }
}
