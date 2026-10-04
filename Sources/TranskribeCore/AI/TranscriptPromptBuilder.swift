import Foundation

/// Renders transcripts as compact, timestamped lines for language models:
///
///     [0:00] Ayşe: Bütçeyi konuşalım.
///     [0:04] Speaker 2: Tamam, rakamlar hazır.
public enum TranscriptPromptBuilder {
    /// Lines never span more than this, so every cited timestamp is close to what it refers to.
    static let maxLineDuration: TimeInterval = 30

    public static func lines(of transcript: Transcript) -> [String] {
        let showNames = transcript.hasSpeakers
        return groupedParagraphs(of: transcript, mergeAcrossSpeakers: !showNames).map { paragraph in
            let stamp = "[\(TranscriptFormatter.timestamp(paragraph.start))]"
            if showNames, let speaker = paragraph.speaker {
                return "\(stamp) \(transcript.name(of: speaker)): \(paragraph.text)"
            }
            return "\(stamp) \(paragraph.text)"
        }
    }

    public static func render(_ transcript: Transcript) -> String {
        lines(of: transcript).joined(separator: "\n")
    }

    /// Splits the rendered transcript into pieces of at most `maxCharacters`, on line boundaries,
    /// in order. A single line longer than the limit is split between words.
    public static func chunks(of transcript: Transcript, maxCharacters: Int) -> [String] {
        chunks(lines: lines(of: transcript), maxCharacters: maxCharacters)
    }

    public static func chunks(lines: [String], maxCharacters: Int) -> [String] {
        let limit = max(1, maxCharacters)
        var result: [String] = []
        var current = ""
        for line in lines.flatMap({ split(line: $0, limit: limit) }) {
            if current.isEmpty {
                current = line
            } else if current.count + 1 + line.count <= limit {
                current += "\n" + line
            } else {
                result.append(current)
                current = line
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Helpers

    /// ParagraphBuilder breaks on every short pause; for prompts we also join same-speaker
    /// paragraphs across pauses (up to `maxLineDuration`) to save tokens.
    private static func groupedParagraphs(of transcript: Transcript, mergeAcrossSpeakers: Bool) -> [Paragraph] {
        ParagraphBuilder.paragraphs(from: transcript.segments).reduce(into: [Paragraph]()) { result, paragraph in
            if let last = result.last,
               mergeAcrossSpeakers || last.speaker == paragraph.speaker,
               paragraph.end - last.start <= maxLineDuration {
                result[result.count - 1].text += " " + paragraph.text
                result[result.count - 1].end = paragraph.end
            } else {
                result.append(paragraph)
            }
        }
    }

    /// Pieces of `line` no longer than `limit`, preferring to break at spaces.
    private static func split(line: String, limit: Int) -> [String] {
        guard line.count > limit else { return [line] }
        var pieces: [String] = []
        var rest = Substring(line)
        while rest.count > limit {
            let window = rest.prefix(limit)
            let endsAtWordBoundary = rest[window.endIndex] == " "
            let cut = endsAtWordBoundary
                ? window.endIndex
                : window.lastIndex(of: " ").flatMap { $0 > window.startIndex ? $0 : nil } ?? window.endIndex
            pieces.append(String(rest[..<cut]))
            rest = rest[cut...].drop { $0 == " " }
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}
