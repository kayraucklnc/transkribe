import Foundation

/// Finds the video-call link in a calendar event (its URL, location or notes).
public enum MeetingLink {
    /// Hosts that serve video calls, matched against the end of a link's host name.
    static let hosts: [(suffix: String, pathPrefix: String?)] = [
        ("meet.google.com", nil),
        ("zoom.us", "/j/"),
        ("zoom.us", "/my/"),
        ("zoom.us", "/w/"),
        ("zoomgov.com", "/j/"),
        ("teams.microsoft.com", "/l/meetup-join"),
        ("teams.microsoft.com", "/meet/"),
        ("teams.live.com", "/meet/"),
        ("webex.com", nil),
        ("facetime.apple.com", "/join"),
        ("whereby.com", nil),
        ("around.co", nil),
        ("app.slack.com", "/huddle/"),
        ("discord.com", "/channels/"),
    ]

    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"'\]\[]+"#, options: [.caseInsensitive])
    private static let trailingJunk = CharacterSet(charactersIn: ".,;:!?)>}'\"")

    /// The first meeting link in `texts`, searched in order. Google Meet, Zoom, Teams, Webex and FaceTime links count.
    public static func find(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            if let url = links(in: text).first(where: isMeeting) { return url }
        }
        return nil
    }

    public static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.scheme?.lowercased().hasPrefix("http") == true else { return false }
        let path = url.path.lowercased()
        return hosts.contains { entry in
            (host == entry.suffix || host.hasSuffix("." + entry.suffix))
                && (entry.pathPrefix.map { path.hasPrefix($0) } ?? (path.count > 1))
        }
    }

    static func links(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        return urlPattern.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[swiftRange]).trimmingCharacters(in: trailingJunk)
            return URL(string: raw)
        }
    }
}
