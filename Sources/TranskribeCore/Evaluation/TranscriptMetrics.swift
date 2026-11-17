import Foundation

/// Measures for comparing speech models on real recordings, most of them without a hand-checked
/// transcript: public benchmarks are read speech in a few languages, and the conversations that
/// matter here are casual calls (in Turkish, too) with two sides and echo.
public enum TranscriptMetrics {
    /// Stretches longer than `limit` seconds with no text at all (on any track), as (start, end).
    public static func silentStretches(_ segments: [RawSegment], duration: TimeInterval,
                                       limit: TimeInterval = 20) -> [Range<TimeInterval>] {
        var found: [Range<TimeInterval>] = []
        var reached: TimeInterval = 0
        for segment in segments.filter(hasText).sorted(by: { $0.start < $1.start }) {
            if segment.start - reached > limit { found.append(reached..<segment.start) }
            reached = max(reached, segment.end)
        }
        if duration - reached > limit { found.append(reached..<duration) }
        return found
    }

    /// Lines with letters that none of `languages` use (e.g. "ð" in a Turkish call): the model
    /// wrote another language's spelling over speech it didn't understand.
    public static func garbledLines(_ segments: [RawSegment], languages: Set<String>) -> [RawSegment] {
        guard let allowed = alphabet(for: languages) else { return [] }
        return segments.filter { segment in
            // Decomposed, so "İ" or "é" is a plain letter plus a mark, and marks aren't letters here.
            segment.text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.contains {
                CharacterSet.letters.contains($0) && !CharacterSet.nonBaseCharacters.contains($0) && !allowed.contains($0)
            }
        }
    }

    /// Letters the languages are written with; nil when one of them isn't known here (no check).
    static func alphabet(for languages: Set<String>) -> CharacterSet? {
        var letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        for language in languages {
            guard let extra = extraLetters[language] else { return nil }
            letters.insert(charactersIn: extra)
        }
        return letters
    }

    private static let extraLetters: [String: String] = [
        "en": "", "tr": "çğıöşüiâîû", "it": "àèéìíîòóù", "de": "äöüß", "fr": "àâæçéèêëîïôœùûüÿ",
        "es": "áéíñóúü", "pt": "áâãàçéêíóôõú", "nl": "éëïóöü",
    ]

    /// Word error rate against a hand-checked transcript: substitutions, insertions and deletions
    /// over the reference's word count, after normalizing case, accents and punctuation.
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = words(reference), hyp = words(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        var previous = Array(0...hyp.count)
        for (i, word) in ref.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: hyp.count)
            for j in hyp.indices {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (word == hyp[j] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[hyp.count]) / Double(ref.count)
    }

    static func words(_ text: String) -> [String] {
        TranscriptSearch.normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func hasText(_ segment: RawSegment) -> Bool {
        !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
