import Foundation

/// A conversation as a document to share: title, who and when, summary, to-dos, then the
/// conversation itself grouped by speaker, with people's real names.
public enum DocumentExport {
    public static func markdown(_ transcript: Transcript, people: [Person] = []) -> String {
        var parts = ["# \(transcript.title)", details(transcript, people: people)]
        if let summary = transcript.summary?.markdown, !summary.isEmpty {
            parts.append(summary)
        }
        if let items = transcript.actionItems, !items.isEmpty {
            parts.append("## To-dos\n" + items.map { item in
                "- [\(item.isDone ? "x" : " ")] \(item.task)" + (item.owner.map { " — \($0)" } ?? "") + (item.due.map { " (\($0))" } ?? "")
            }.joined(separator: "\n"))
        }
        parts.append("## Conversation\n" + turns(transcript, people: people).map { turn in
            turn.name.map { "**\($0)** · \(TranscriptFormatter.timestamp(turn.start))\n\(turn.text)" }
                ?? "\(TranscriptFormatter.timestamp(turn.start))\n\(turn.text)"
        }.joined(separator: "\n\n"))
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// The same document as styled HTML, for PDF.
    public static func html(_ transcript: Transcript, people: [Person] = []) -> String {
        var body = "<h1>\(escape(transcript.title))</h1><p class=meta>\(escape(details(transcript, people: people)))</p>"
        if let items = transcript.actionItems, !items.isEmpty {
            body += "<h2>To-dos</h2><ul>" + items.map { item in
                "<li>\(item.isDone ? "☑" : "☐") \(escape(item.task))" + (item.owner.map { " <span class=meta>— \(escape($0))</span>" } ?? "")
                    + (item.due.map { " <span class=meta>(\(escape($0)))</span>" } ?? "") + "</li>"
            }.joined() + "</ul>"
        }
        if let summary = transcript.summary?.markdown, !summary.isEmpty {
            body += "<h2>Summary</h2>" + summary.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { line in
                    if line.hasPrefix("#") { return "<h3>\(escape(line.drop { $0 == "#" || $0 == " " }))</h3>" }
                    let text = line.hasPrefix("- ") ? "• " + line.dropFirst(2) : Substring(line)
                    return "<p>\(escape(text.replacingOccurrences(of: "**", with: "")))</p>"
                }.joined()
        }
        body += "<h2>Conversation</h2>" + turns(transcript, people: people).map { turn in
            "<p><b>\(escape(turn.name ?? ""))</b> <span class=meta>\(TranscriptFormatter.timestamp(turn.start))</span><br>\(escape(turn.text))</p>"
        }.joined()
        return """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, 'Helvetica Neue'; font-size: 11pt; line-height: 1.45; color: #1d1d1f; }
        h1 { font-size: 22pt; margin-bottom: 2pt; } h2 { font-size: 14pt; margin-top: 18pt; } h3 { font-size: 11.5pt; }
        .meta { color: #86868b; } p { margin: 0 0 8pt 0; } li { margin-bottom: 4pt; }
        </style></head><body>\(body)</body></html>
        """
    }

    // MARK: - Helpers

    struct Turn {
        var name: String?
        var start: TimeInterval
        var text: String
    }

    static func turns(_ transcript: Transcript, people: [Person]) -> [Turn] {
        transcript.segments.reduce(into: [Turn]()) { result, segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let name = transcript.hasSpeakers ? segment.speaker.map { transcript.name(of: $0, people: people) } : nil
            if let last = result.last, last.name == name {
                result[result.count - 1].text += " " + text
            } else {
                result.append(Turn(name: name, start: segment.start, text: text))
            }
        }
    }

    private static func details(_ transcript: Transcript, people: [Person]) -> String {
        let names = transcript.speakers.map { transcript.name(of: $0, people: people) }
        let when = transcript.createdAt.formatted(date: .long, time: .shortened)
        let length = TranscriptFormatter.timestamp(transcript.duration)
        return ([when, length] + (transcript.hasSpeakers ? [names.joined(separator: ", ")] : [])).joined(separator: " · ")
    }

    private static func escape<S: StringProtocol>(_ text: S) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
