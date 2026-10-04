import Foundation

extension AIModel {
    /// Finds timestamp citations like `[12:34]` or `[1:02:03]` in model output so they can be made clickable.
    /// Ranges include the brackets. Malformed values (e.g. `[1:75]`) are skipped.
    public static func parseTimestamps(in markdown: String) -> [(range: Range<String.Index>, seconds: TimeInterval)] {
        let pattern = #/\[(?:(\d{1,2}):)?(\d{1,3}):(\d{2})\]/#
        return markdown.matches(of: pattern).compactMap { match in
            let (_, hours, minutes, seconds) = match.output
            guard let m = Int(minutes), let s = Int(seconds), s < 60 else { return nil }
            if let hours {
                guard let h = Int(hours), m < 60 else { return nil }
                return (match.range, TimeInterval(h * 3600 + m * 60 + s))
            }
            return (match.range, TimeInterval(m * 60 + s))
        }
    }
}

/// Renders a multi-turn conversation as one prompt, for backends that take a single prompt.
enum ConversationRenderer {
    static func prompt(from messages: [AIMessage]) -> String {
        guard let last = messages.last else { return "" }
        guard messages.count > 1 else { return last.text }
        let history = messages.dropLast().map { message in
            let speaker = message.role == .user ? "User" : "Assistant"
            return "<\(speaker.lowercased())>\n\(message.text)\n</\(speaker.lowercased())>"
        }
        return """
        <conversation_so_far>
        \(history.joined(separator: "\n"))
        </conversation_so_far>

        Continue the conversation: reply to the user's latest message below.

        \(last.text)
        """
    }
}
