import Foundation

public enum TitleGenerator {
    static let maxWords = 8
    public static let recordingPrefix = "Recording · "

    public static func title(forFile url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.hasPrefix(".") ? "Untitled" : name
    }

    public static func recordingTitle(at date: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return recordingPrefix + formatter.string(from: date)
    }

    /// First few words of the transcript, used to replace generic recording titles.
    public static func suggestedTitle(from segments: [Segment]) -> String? {
        let words = segments.lazy
            .flatMap { $0.text.split(whereSeparator: \.isWhitespace) }
            .prefix(maxWords + 1)
        guard !words.isEmpty else { return nil }
        let title = words.prefix(maxWords).joined(separator: " ")
        return words.count > maxWords ? title + "…" : title
    }
}
