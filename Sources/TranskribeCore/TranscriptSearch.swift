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

    public struct Hit: Identifiable, Equatable, Sendable {
        public var id: Segment.ID
        public var start: TimeInterval
        public var text: String
        public var speaker: Int?
    }

    /// Lines that contain every search term, in conversation order, for "jump to" results.
    public static func hits(in transcript: Transcript, query: String) -> [Hit] {
        let terms = terms(of: query)
        guard !terms.isEmpty else { return [] }
        return transcript.segments.compactMap { segment in
            let text = normalize(segment.text)
            guard terms.allSatisfy(text.contains) else { return nil }
            return Hit(id: segment.id, start: segment.start, text: segment.text.trimmingCharacters(in: .whitespaces), speaker: segment.speaker)
        }
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
