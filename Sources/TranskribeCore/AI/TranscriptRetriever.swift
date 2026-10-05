import Foundation

/// Picks the parts of a transcript most relevant to a question, for models whose context
/// can't hold the whole transcript. Keyword overlap, accent- and case-insensitive, with
/// prefix matching so Turkish suffixes still match (`bütçe` finds `bütçeyi`, `bütçesi`).
public enum TranscriptRetriever {
    /// Joins non-adjacent excerpts in the rendered context.
    public static let gapMarker = "…"

    /// Chunks the transcript into small pieces and returns the most relevant ones that fit in
    /// `budget` characters, joined in original order with `gapMarker` lines between gaps.
    public static func excerpts(for question: String, in transcript: Transcript, budget: Int) -> String {
        let chunkSize = min(max(budget / 6, 400), 2_000)
        let chunks = TranscriptPromptBuilder.chunks(of: transcript, maxCharacters: chunkSize)
        let picked = retrieveIndices(question: question, from: chunks, budget: budget)
        var parts: [String] = []
        var previous = -1
        for index in picked {
            if index != previous + 1 { parts.append(gapMarker) }
            parts.append(chunks[index])
            previous = index
        }
        if previous < chunks.count - 1 { parts.append(gapMarker) }
        return parts.joined(separator: "\n")
    }

    /// The best chunks for `question` whose total length (plus newlines) fits in `budget`, in original order.
    public static func retrieve(question: String, from chunks: [String], budget: Int) -> [String] {
        retrieveIndices(question: question, from: chunks, budget: budget).map { chunks[$0] }
    }

    static func retrieveIndices(question: String, from chunks: [String], budget: Int) -> [Int] {
        guard !chunks.isEmpty else { return [] }
        let scores = scores(question: question, chunks: chunks)
        // Relevant chunks best first; leftover room goes to an even spread of the rest for overall context.
        let relevant = chunks.indices.filter { scores[$0] > 0 }.sorted { a, b in
            scores[a] != scores[b] ? scores[a] > scores[b] : a < b
        }
        let ranked = relevant + evenlySpread(count: chunks.count).filter { scores[$0] == 0 }
        var used = 0
        var picked: [Int] = []
        for index in ranked {
            let cost = chunks[index].count + (picked.isEmpty ? 0 : 1)
            guard used + cost <= budget else { continue }
            used += cost
            picked.append(index)
        }
        return picked.sorted()
    }

    /// Relevance per chunk: IDF-weighted matched question terms, plus a share of the best
    /// neighbor's score so context around a hit is preferred over unrelated chunks.
    static func scores(question: String, chunks: [String]) -> [Double] {
        let terms = Set(keywords(in: question))
        guard !terms.isEmpty else { return chunks.map { _ in 0 } }
        let chunkWords = chunks.map { Set(words(in: $0)) }
        let hits: [[String: Bool]] = chunkWords.map { words in
            Dictionary(uniqueKeysWithValues: terms.map { term in (term, words.contains { matches(word: $0, term: term) }) })
        }
        let count = Double(chunks.count)
        let idf = Dictionary(uniqueKeysWithValues: terms.map { term in
            let documentFrequency = Double(hits.filter { $0[term] == true }.count)
            return (term, log(1 + count / max(documentFrequency, 1)))
        })
        let base = hits.map { match in
            terms.reduce(0.0) { $0 + (match[$1] == true ? idf[$1] ?? 0 : 0) }
        }
        return base.indices.map { index in
            let before = index > 0 ? base[index - 1] : 0
            let after = index + 1 < base.count ? base[index + 1] : 0
            return base[index] + 0.3 * max(before, after)
        }
    }

    // MARK: - Text processing

    /// Content words of `text`: normalized, without stop words and very short words.
    static func keywords(in text: String) -> [String] {
        words(in: text).filter { word in
            let hasDigit = word.contains(where: \.isNumber)
            return (word.count >= 3 || (hasDigit && word.count >= 2)) && !stopWords.contains(word)
        }
    }

    static func words(in text: String) -> [String] {
        TranscriptSearch.normalize(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Prefix match on a stem so inflected forms match: `toplanti` ↔ `toplantida`, `price` ↔ `pricing`.
    static func matches(word: String, term: String) -> Bool {
        if word == term { return true }
        let stem = term.prefix(max(4, term.count - 3))
        return stem.count >= 4 && word.hasPrefix(stem)
    }

    /// Normalized (lowercase, no diacritics, ı → i) common English and Turkish words.
    static let stopWords: Set<String> = [
        // English
        "the", "and", "are", "was", "were", "for", "from", "with", "that", "this", "these", "those",
        "what", "when", "where", "which", "who", "whom", "whose", "why", "how", "did", "does", "done",
        "about", "any", "all", "has", "have", "had", "they", "them", "their", "there", "then", "than",
        "you", "your", "our", "his", "her", "she", "him", "its", "not", "but", "can", "could", "would",
        "should", "will", "into", "out", "over", "some", "say", "said", "says", "tell", "told", "talk",
        "talked", "mention", "mentioned", "discuss", "discussed", "anyone", "someone", "something",
        "transcript", "conversation", "please", "thing", "things", "also", "just",
        // Turkish
        "bir", "ben", "sen", "biz", "siz", "onlar", "bunu", "buna", "bunun", "sunu", "onu", "ona", "onun",
        "icin", "ile", "ama", "fakat", "gibi", "daha", "cok", "olan", "olarak", "var", "yok", "mi", "mu",
        "neden", "nicin", "nasil", "hangi", "kim", "kimi", "kime", "kimin", "nerede", "nereye", "ne",
        "zaman", "acaba", "hakkinda", "dedi", "demis", "soyledi", "soylemis", "konustu", "konusuldu",
        "konustular", "bahsetti", "bahsedildi", "ettiler", "etti", "oldu", "olur", "olsun", "kadar",
        "sonra", "once", "her", "hep", "hic", "ise", "veya", "yani", "seyi", "sey", "seyler", "bana",
        "sana", "bize", "size", "konusmada", "lutfen", "neler", "nedir", "midir",
    ]

    private static func evenlySpread(count: Int) -> [Int] {
        // Breadth-first bisection order: 0, last, middle, quarters… so a partial pick covers the whole span.
        var order: [Int] = []
        var seen = Set<Int>()
        var queue: [(Int, Int)] = [(0, count - 1)]
        if seen.insert(0).inserted { order.append(0) }
        if seen.insert(count - 1).inserted { order.append(count - 1) }
        while !queue.isEmpty {
            let (low, high) = queue.removeFirst()
            guard high - low > 1 else { continue }
            let mid = (low + high) / 2
            if seen.insert(mid).inserted { order.append(mid) }
            queue.append((low, mid))
            queue.append((mid, high))
        }
        return order
    }
}
