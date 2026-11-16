import Foundation

/// A meeting open in a browser tab: which service, and the meeting's own code when the page
/// shows one (Meet's "abc-defg-hij", a Zoom meeting number), to match it with the calendar.
public struct BrowserMeeting: Equatable, Sendable {
    public enum Service: String, Sendable {
        case googleMeet = "Google Meet"
        case zoom = "Zoom"
        case teams = "Teams"
        case webex = "Webex"
        case whereby = "Whereby"
        case slack = "Slack"
    }

    public let service: Service
    public let code: String?

    public init(service: Service, code: String?) {
        self.service = service
        self.code = code
    }

    // MARK: - Reading tabs

    private static let meetCode = try! NSRegularExpression(pattern: #"\b([a-z]{3}-[a-z]{4}-[a-z]{3})\b"#)
    private static let zoomNumber = try! NSRegularExpression(pattern: #"/(?:wc|j|s)/(?:join/)?(\d{9,12})"#)

    /// The meeting a tab's address is in. Home and landing pages (meet.google.com, zoom.us) don't count.
    public static func from(url: URL) -> BrowserMeeting? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if on("meet.google.com") {
            return firstMatch(meetCode, in: path).map { BrowserMeeting(service: .googleMeet, code: $0) }
        }
        if on("zoom.us") || on("zoomgov.com") {
            guard path.hasPrefix("/wc/") || path.hasPrefix("/j/") || path.hasPrefix("/s/") else { return nil }
            return BrowserMeeting(service: .zoom, code: firstMatch(zoomNumber, in: path))
        }
        if on("teams.microsoft.com") || on("teams.live.com") {
            // Teams on the web keeps one address for chats and calls, so the open app counts.
            return BrowserMeeting(service: .teams, code: nil)
        }
        if on("webex.com"), path.count > 1 { return BrowserMeeting(service: .webex, code: nil) }
        if on("whereby.com"), path.count > 1 { return BrowserMeeting(service: .whereby, code: nil) }
        if on("app.slack.com"), path.contains("/huddle/") { return BrowserMeeting(service: .slack, code: nil) }
        return nil
    }

    /// The meeting a browser window's title shows, for browsers that only share titles (Firefox, Zen).
    /// "Meet - abc-defg-hij — Mozilla Firefox", "Zoom Meeting", "Meeting with Ada | Microsoft Teams".
    public static func from(windowTitle title: String) -> BrowserMeeting? {
        let lower = title.lowercased()
        if lower.range(of: #"^meet\s*[-–—]\s"#, options: .regularExpression) != nil || lower.contains("google meet"),
           let code = firstMatch(meetCode, in: lower) {
            return BrowserMeeting(service: .googleMeet, code: code)
        }
        if lower.contains("zoom meeting") || lower.contains("zoom webinar") {
            return BrowserMeeting(service: .zoom, code: nil)
        }
        if lower.contains("microsoft teams") { return BrowserMeeting(service: .teams, code: nil) }
        if lower.contains("webex") { return BrowserMeeting(service: .webex, code: nil) }
        return nil
    }

    /// Whether a calendar event's call link is this meeting (same Meet code or Zoom number).
    public func matches(link: URL) -> Bool {
        guard let code, let other = BrowserMeeting.from(url: link), other.service == service else { return false }
        return other.code == code
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange])
    }
}
