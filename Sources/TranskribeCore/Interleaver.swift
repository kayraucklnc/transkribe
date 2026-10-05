import Foundation

/// When two people talk over each other, each channel produces a long turn. Splitting a long
/// turn at the sentence where the other person cut in puts the conversation back in the order
/// it happened: "…ses derinden mi geliyor bana?" → "Yok. Selam." → "Bir konuşabilir misiniz?"
public enum Interleaver {
    /// Only cut-ins with some substance split a turn; quick reactions become tapbacks instead.
    static let minimumCutInWords = 3
    /// The sentence end used as a split point must be close to when the other person started.
    static let maxLookBack: TimeInterval = 4
    static let maxLookAhead: TimeInterval = 0.6

    public static func interleave(_ segments: [Segment]) -> [Segment] {
        let cutIns = segments.filter { wordCount($0) >= minimumCutInWords && Reaction.Kind.classify($0.text) == nil }
        return segments.flatMap { segment -> [Segment] in
            guard segment.words.count >= 4 else { return [segment] }
            let times = cutIns
                .filter { $0.speaker != segment.speaker && $0.start > segment.start + 0.5 && $0.start < segment.end - 0.5 }
                .map(\.start)
            let splits = Set(times.compactMap { splitIndex(in: segment.words, near: $0) })
            guard !splits.isEmpty else { return [segment] }
            var pieces: [Segment] = []
            var from = 0
            for index in splits.sorted() + [segment.words.count - 1] where index >= from {
                let words = Array(segment.words[from...index])
                pieces.append(Segment(
                    id: TrackMerger.stableID(track: 900 + (segment.speaker ?? 0), start: words[0].start),
                    start: words[0].start,
                    end: words[words.count - 1].end,
                    text: words.map(\.text).joined().trimmingCharacters(in: .whitespaces),
                    speaker: segment.speaker,
                    words: words
                ))
                from = index + 1
            }
            return pieces
        }
        .sorted { $0.start < $1.start }
    }

    /// Index of the last word of a sentence that ends just before `time`, or nil.
    private static func splitIndex(in words: [Word], near time: TimeInterval) -> Int? {
        words.indices.dropLast().last { index in
            let word = words[index]
            let trimmed = word.text.trimmingCharacters(in: .whitespaces)
            return word.end <= time + maxLookAhead && word.end >= time - maxLookBack
                && (trimmed.last.map { ".?!…".contains($0) } ?? false)
        }
    }

    private static func wordCount(_ segment: Segment) -> Int {
        segment.words.isEmpty ? segment.text.split(whereSeparator: \.isWhitespace).count : segment.words.count
    }
}
