import Foundation

/// Accent-, case- and Turkish-dotless-i-insensitive search over transcripts.
public enum TranscriptSearch {
    public static func matches(_ transcript: Transcript, query: String) -> Bool {
        let terms = terms(of: query)
        guard !terms.isEmpty else { return true }
        let haystack = normalize(([transcript.title] + transcript.segments.map(\.text)).joined(separator: " "))
        return terms.allSatisfy(haystack.contains)
    }

    public static func matchingSegmentIDs(in transcript: Transcript, query: String) -> Set<Segment.ID> {
        let terms = terms(of: query)
        guard !terms.isEmpty else { return [] }
        return Set(transcript.segments.filter { segment in
            let text = normalize(segment.text)
            return terms.contains(where: text.contains)
        }.map(\.id))
    }

    public static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "I", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func terms(of query: String) -> [String] {
        normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
