import Foundation

public struct Paragraph: Identifiable, Equatable, Sendable {
    public var id: Segment.ID
    public var start: TimeInterval
    public var end: TimeInterval
    public var speaker: Int?
    public var text: String
    public var segmentIDs: [Segment.ID]
    /// Timed words for highlighting. Segments without word timings contribute one "word".
    public var words: [Word]
}

/// Groups Whisper's short segments into readable paragraphs: a new paragraph starts on a
/// pause, a speaker change, or when the current one gets long.
public enum ParagraphBuilder {
    static let maxGap: TimeInterval = 1.5
    static let maxDuration: TimeInterval = 30

    public static func paragraphs(from segments: [Segment]) -> [Paragraph] {
        segments.reduce(into: [Paragraph]()) { result, segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let words = segment.words.isEmpty
                ? [Word(start: segment.start, end: segment.end, text: " " + text)]
                : segment.words.map { word in
                    word.text.hasPrefix(" ") ? word : Word(start: word.start, end: word.end, text: " " + word.text)
                }
            if let last = result.last,
               last.speaker == segment.speaker,
               segment.start - last.end <= maxGap,
               segment.end - last.start <= maxDuration {
                result[result.count - 1].text += " " + text
                result[result.count - 1].end = segment.end
                result[result.count - 1].segmentIDs.append(segment.id)
                result[result.count - 1].words += words
            } else {
                result.append(Paragraph(id: segment.id, start: segment.start, end: segment.end,
                                        speaker: segment.speaker, text: text, segmentIDs: [segment.id], words: words))
            }
        }
    }
}
