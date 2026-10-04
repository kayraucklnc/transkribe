import Foundation

/// Learns names and terms from the user's fixes, so the same mishearing doesn't happen again.
public enum CorrectionLearner {
    /// Everyday words aren't worth adding even when corrected.
    static let common: Set<String> = [
        "the", "and", "but", "for", "you", "are", "was", "were", "this", "that", "with", "have", "has", "had", "not",
        "bir", "ve", "ama", "için", "bu", "şu", "çok", "var", "yok", "ben", "sen", "biz", "siz", "gibi", "daha",
        "che", "non", "per", "una", "sono", "con", "come", "anche", "più",
    ]

    /// Words that replaced misheard ones (substitutions, not additions), new to `known`.
    public static func newTerms(from old: String, to new: String, known: [String]) -> [String] {
        let before = words(old), after = words(new)
        let knownSet = Set(known.map { $0.lowercased() })
        var terms: [String] = []
        for (removed, added) in substitutions(before, after) where !removed.isEmpty && !added.isEmpty {
            for word in added {
                let key = word.lowercased()
                guard word.count >= 3, word.contains(where: \.isLetter), !common.contains(key), !knownSet.contains(key),
                      !terms.contains(where: { $0.lowercased() == key }) else { continue }
                terms.append(word)
            }
        }
        return terms
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { !$0.isEmpty }
    }

    /// Runs of words that differ between `a` and `b`, aligned by their longest common subsequence.
    private static func substitutions(_ a: [String], _ b: [String]) -> [([String], [String])] {
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i].lowercased() == b[j].lowercased() ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [([String], [String])] = []
        var i = 0, j = 0
        var removed: [String] = [], added: [String] = []
        func flush() {
            if !removed.isEmpty || !added.isEmpty { result.append((removed, added)) }
            removed = []
            added = []
        }
        while i < n || j < m {
            if i < n, j < m, a[i].lowercased() == b[j].lowercased() {
                flush()
                i += 1
                j += 1
            } else if j < m, i == n || table[i][j + 1] >= table[i + 1][j] {
                added.append(b[j])
                j += 1
            } else {
                removed.append(a[i])
                i += 1
            }
        }
        flush()
        return result
    }
}

/// Applying a text edit to the segments behind one paragraph.
public enum SegmentEditing {
    /// The paragraph made of `ids` becomes one segment with `text`, spread over its original time
    /// so playback highlighting still roughly follows. Empty text removes it.
    public static func replacing(_ ids: [Segment.ID], in segments: [Segment], with text: String) -> [Segment] {
        let idSet = Set(ids)
        let edited = segments.filter { idSet.contains($0.id) }
        guard let first = edited.first else { return segments }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let others = segments.filter { !idSet.contains($0.id) }
        guard !trimmed.isEmpty else { return others }
        let start = edited.map(\.start).min() ?? first.start, end = edited.map(\.end).max() ?? first.end
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let total = Double(tokens.reduce(0) { $0 + $1.count })
        var cursor = start
        let words = tokens.enumerated().map { index, token -> Word in
            let length = (end - start) * Double(token.count) / max(1, total)
            defer { cursor += length }
            return Word(start: cursor, end: index == tokens.count - 1 ? end : cursor + length, text: index == 0 ? token : " " + token)
        }
        let replacement = Segment(id: first.id, start: start, end: end, text: trimmed, speaker: first.speaker, words: words)
        return (others + [replacement]).sorted { $0.start < $1.start }
    }
}
