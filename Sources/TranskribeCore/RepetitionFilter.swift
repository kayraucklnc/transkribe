import Foundation

/// Removes Whisper's runaway repetition loops ("olununununun…", "thank you. thank you. …")
/// while leaving natural repetition ("no no no", "hahaha") alone.
public enum RepetitionFilter {
    /// A chunk of 2–40 characters repeated four or more times in a row.
    private static let repeatedChunk = try! NSRegularExpression(pattern: #"(.{2,40}?)\1{3,}"#, options: [.caseInsensitive])
    /// A single character repeated eight or more times.
    private static let repeatedCharacter = try! NSRegularExpression(pattern: #"(.)\1{7,}"#)

    public static func collapse(_ text: String) -> String {
        var result = text
        for regex in [repeatedChunk, repeatedCharacter] {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1"
            )
        }
        return result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when Whisper got stuck repeating itself, so the passage should be transcribed again.
    public static func isLoop(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }
        if collapse(trimmed).count < trimmed.count * 2 / 3 { return true }
        let words = trimmed.lowercased().split(whereSeparator: \.isWhitespace)
        return longestRun(of: words.map(String.init)) >= minimumWordRepeats
    }

    /// Cleans per-word timings the same way as text: runaway repeats collapse to one word and
    /// filler made only of dots disappears. Bubbles render words, so this keeps them honest.
    public static func clean(words: [Word]) -> [Word] {
        var result: [Word] = []
        var runCount = 0
        for word in words {
            let core = word.text.trimmingCharacters(in: .whitespaces)
            if core.count >= 4, core.allSatisfy({ $0 == "." || $0 == "…" }) { continue }
            let collapsed = collapse(core)
            guard !collapsed.isEmpty else { continue }
            let key = TranscriptSearch.normalize(collapsed).trimmingCharacters(in: .punctuationCharacters)
            if let last = result.last,
               TranscriptSearch.normalize(last.text.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .punctuationCharacters) == key {
                runCount += 1
                if runCount >= minimumWordRepeats - 1 {
                    // Part of a runaway run: keep only the first occurrence.
                    result[result.count - 1].end = word.end
                    continue
                }
            } else {
                runCount = 0
            }
            result.append(Word(start: word.start, end: word.end, text: word.text.hasPrefix(" ") ? " " + collapsed : collapsed))
        }
        return removeRepeatedRuns(result)
    }

    /// The same word this many times in a row is a loop, not speech ("yaza yaza yaza yaza").
    static let minimumWordRepeats = 4

    private static func longestRun(of words: [String]) -> Int {
        var best = 0, current = 0
        var previous: String?
        for word in words {
            let key = word.trimmingCharacters(in: .punctuationCharacters)
            current = key == previous ? current + 1 : 1
            previous = key
            best = max(best, current)
        }
        return best
    }

    /// After the first pass, drop the extra copies that were kept before a run was recognized.
    private static func removeRepeatedRuns(_ words: [Word]) -> [Word] {
        var result: [Word] = []
        for word in words {
            let key = TranscriptSearch.normalize(word.text.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .punctuationCharacters)
            let tail = result.suffix(minimumWordRepeats - 1)
            if tail.count == minimumWordRepeats - 1,
               tail.allSatisfy({ TranscriptSearch.normalize($0.text.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .punctuationCharacters) == key }) {
                continue
            }
            result.append(word)
        }
        // Collapse any remaining run of identical words to one.
        var collapsed: [Word] = []
        var index = 0
        while index < result.count {
            let key = TranscriptSearch.normalize(result[index].text.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .punctuationCharacters)
            var next = index + 1
            while next < result.count,
                  TranscriptSearch.normalize(result[next].text.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .punctuationCharacters) == key {
                next += 1
            }
            if next - index >= minimumWordRepeats - 1 {
                var word = result[index]
                word.end = result[next - 1].end
                collapsed.append(word)
            } else {
                collapsed.append(contentsOf: result[index..<next])
            }
            index = next
        }
        return collapsed
    }
}
