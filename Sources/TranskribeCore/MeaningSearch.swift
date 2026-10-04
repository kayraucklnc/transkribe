import Foundation

/// Search by meaning: a model turns the query into the words people would actually have said,
/// in every language the user speaks, and conversations are searched for any of them.
public enum MeaningSearch {
    static let maximumTerms = 14

    public static func system(languages: [String]) -> String {
        let names = languages.compactMap(Prompts.languageName(for:))
        let spoken = names.isEmpty ? "English and Turkish" : ListFormatter.localizedString(byJoining: names)
        return """
        You help search transcripts of spoken conversations in \(spoken). Given a search, reply with only a \
        JSON array of short words or phrases people would actually say about it. Give at least three for EACH \
        language (\(spoken)): synonyms, related everyday words, and word stems that also match inflected forms \
        (e.g. "fiyat" matches "fiyatı", "fiyatlar"). Lowercase, at most 14 in total, no explanations.
        Example for "price" in English, Turkish and Italian:
        ["price", "cost", "how much", "fiyat", "ücret", "kaç lira", "prezzo", "costa", "quanto"]
        """
    }

    /// Search terms from the model's reply (a JSON array, or a plain list), the query first.
    public static func parseTerms(_ reply: String, query: String) -> [String] {
        var raw: [String] = []
        if let open = reply.firstIndex(of: "["), let close = reply.lastIndex(of: "]"), open < close,
           let array = try? JSONDecoder().decode([String].self, from: Data(reply[open...close].utf8)) {
            raw = array
        } else {
            raw = reply.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")) }
                .map { $0.components(separatedBy: ":").last ?? $0 }
        }
        var terms: [String] = []
        for term in [query] + raw {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
            guard cleaned.count >= 2, !terms.contains(cleaned) else { continue }
            terms.append(cleaned)
        }
        return Array(terms.prefix(maximumTerms))
    }

    /// Lines that mention any of the terms, in conversation order.
    public static func hits(in transcript: Transcript, terms: [String]) -> [TranscriptSearch.Hit] {
        let needles = terms.map(TranscriptSearch.normalize)
        return transcript.segments.compactMap { segment in
            let text = TranscriptSearch.normalize(segment.text)
            guard needles.contains(where: { matches($0, in: text) }) else { return nil }
            return TranscriptSearch.Hit(id: segment.id, start: segment.start,
                                        text: segment.text.trimmingCharacters(in: .whitespaces), speaker: segment.speaker)
        }
    }

    /// A term matches at the start of a word, so stems catch inflections ("fiyat" → "fiyatı")
    /// but short words don't match inside others ("pay" isn't in "yapay").
    static func matches(_ term: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: term, range: searchRange) {
            if found.lowerBound == text.startIndex || !text[text.index(before: found.lowerBound)].isLetter { return true }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }

    /// Conversations with any match, most matches first.
    public static func rank(_ transcripts: [Transcript], terms: [String]) -> [Transcript] {
        transcripts.map { ($0, hits(in: $0, terms: terms).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
