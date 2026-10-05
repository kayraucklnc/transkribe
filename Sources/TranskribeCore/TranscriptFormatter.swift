import Foundation

/// Renders transcripts for the clipboard and for export.
public enum TranscriptFormatter {
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    public static func srtTimestamp(_ seconds: TimeInterval) -> String {
        let millis = max(0, Int((seconds * 1000).rounded()))
        let (h, m, s, ms) = (millis / 3_600_000, (millis % 3_600_000) / 60_000, (millis % 60_000) / 1000, millis % 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    /// Flowing text. Consecutive segments from the same speaker form one paragraph.
    public static func plainText(_ transcript: Transcript) -> String {
        paragraphs(of: transcript)
            .map { paragraph in
                let text = paragraph.texts.joined(separator: " ")
                guard transcript.hasSpeakers, let speaker = paragraph.speaker else { return text }
                return "\(transcript.name(of: speaker)): \(text)"
            }
            .joined(separator: "\n\n")
    }

    public static func srt(_ transcript: Transcript) -> String {
        nonEmpty(transcript.segments).enumerated().map { index, segment in
            let label = speakerLabel(segment, in: transcript).map { "\($0): " } ?? ""
            return "\(index + 1)\n\(srtTimestamp(segment.start)) --> \(srtTimestamp(segment.end))\n\(label)\(trimmed(segment.text))\n"
        }
        .joined(separator: "\n")
    }

    public static func markdown(_ transcript: Transcript) -> String {
        let lines = nonEmpty(transcript.segments).map { segment in
            let label = speakerLabel(segment, in: transcript).map { " *\($0)*" } ?? ""
            return "**[\(timestamp(segment.start))]**\(label) \(trimmed(segment.text))"
        }
        return "# \(transcript.title)\n\n" + lines.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Helpers

    private struct Paragraph {
        var speaker: Int?
        var texts: [String]
    }

    private static func paragraphs(of transcript: Transcript) -> [Paragraph] {
        nonEmpty(transcript.segments).reduce(into: [Paragraph]()) { result, segment in
            let text = trimmed(segment.text)
            if let last = result.last, last.speaker == segment.speaker {
                result[result.count - 1].texts.append(text)
            } else {
                result.append(Paragraph(speaker: segment.speaker, texts: [text]))
            }
        }
    }

    private static func speakerLabel(_ segment: Segment, in transcript: Transcript) -> String? {
        guard transcript.hasSpeakers else { return nil }
        return segment.speaker.map(transcript.name(of:))
    }

    private static func nonEmpty(_ segments: [Segment]) -> [Segment] {
        segments.filter { !trimmed($0.text).isEmpty }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
