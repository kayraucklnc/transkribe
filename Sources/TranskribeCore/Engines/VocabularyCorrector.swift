import Foundation

/// Fixes near-misses of the user's own names and terms ("Flaying Papers" → "Flying Papers",
/// "podrosu" → "bordrosu"). Only very close matches change, so ordinary words are left alone.
public enum VocabularyCorrector {
    /// Share of characters that may differ for a word to count as a misspelling of a term.
    static let maximumDistanceRatio = 0.25

    public static func correct(_ text: String, vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for term in vocabulary.sorted(by: { $0.split(separator: " ").count > $1.split(separator: " ").count }) {
            let length = term.split(separator: " ").count
            guard length > 0, words.count >= length else { continue }
            var index = 0
            while index + length <= words.count {
                let window = words[index..<(index + length)]
                let (core, suffix) = splitPunctuation(window.joined(separator: " "))
                if isNearMatch(core, term) {
                    words.replaceSubrange(index..<(index + length), with: [term + suffix])
                }
                index += 1
            }
        }
        return words.joined(separator: " ")
    }

    /// Same as `correct`, for single-word terms on per-word timings.
    public static func correct(words: [Word], vocabulary: [String]) -> [Word] {
        let singles = vocabulary.filter { !$0.contains(" ") }
        guard !singles.isEmpty else { return words }
        return words.map { word in
            let leading = word.text.prefix { $0 == " " }
            let (core, suffix) = splitPunctuation(String(word.text.dropFirst(leading.count)))
            guard let term = singles.first(where: { isNearMatch(core, $0) }) else { return word }
            return Word(start: word.start, end: word.end, text: leading + term + suffix)
        }
    }

    static func isNearMatch(_ candidate: String, _ term: String) -> Bool {
        let a = TranscriptSearch.normalize(candidate), b = TranscriptSearch.normalize(term)
        guard b.count >= 4, a != b || candidate != term else { return a == b }
        if a == b { return true }
        // Turkish suffixes make real words look alike ("bordro" vs "bordrosu"): allow at most
        // one letter of length difference.
        guard abs(a.count - b.count) <= 1 else { return false }
        return Double(distance(Array(a), Array(b))) / Double(b.count) <= maximumDistanceRatio
    }

    private static func splitPunctuation(_ text: String) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .punctuationCharacters)
        guard let range = text.range(of: trimmed), !trimmed.isEmpty else { return (text, "") }
        return (trimmed, String(text[range.upperBound...]))
    }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + [Int](repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// Turns raw recognizer output into segments with per-word timings.
public enum SegmentAssembly {
    /// A new segment starts after a sentence end or a pause this long.
    static let pause: TimeInterval = 0.8

    /// Parakeet-style subword tokens, where "▁" (or a leading space) starts a new word.
    public static func fromTokens(_ tokens: [(text: String, start: TimeInterval, end: TimeInterval)]) -> [RawSegment] {
        var words: [(String, TimeInterval, TimeInterval)] = []
        for token in tokens {
            let startsWord = token.text.hasPrefix("▁") || token.text.hasPrefix(" ") || words.isEmpty
            let piece = token.text.replacingOccurrences(of: "▁", with: "").trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if startsWord {
                words.append((piece, token.start, token.end))
            } else {
                words[words.count - 1].0 += piece
                words[words.count - 1].2 = token.end
            }
        }
        return fromWordRuns(words.map { (" " + $0.0, $0.1, $0.2) })
    }

    /// Word-level runs (text may start with a space), grouped into sentences.
    public static func fromWordRuns(_ runs: [(text: String, start: TimeInterval, end: TimeInterval)]) -> [RawSegment] {
        var segments: [RawSegment] = []
        var current: [Word] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(RawSegment(start: first.start, end: last.end,
                                       text: current.map(\.text).joined().trimmingCharacters(in: .whitespaces), words: current))
            current = []
        }
        for run in runs {
            let text = run.text.hasPrefix(" ") ? run.text : " " + run.text
            if let last = current.last, run.start - last.end > pause { flush() }
            current.append(Word(start: run.start, end: run.end, text: text))
            if let mark = text.trimmingCharacters(in: .whitespaces).last, ".?!…".contains(mark) { flush() }
        }
        flush()
        return segments
    }
}
