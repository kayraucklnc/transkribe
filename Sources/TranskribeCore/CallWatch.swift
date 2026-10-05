import Foundation

/// Apps people take calls in, by bundle identifier.
public enum CallApps {
    static let names: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "com.apple.FaceTime": "FaceTime",
        "com.apple.avconferenced": "FaceTime", // FaceTime and phone calls run their audio here
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.skype.skype": "Skype",
        "ru.keepcoder.Telegram": "Telegram",
        "org.whispersystems.signal-desktop": "Signal",
        // Google Meet and other web calls run in the browser.
        "com.google.Chrome": "Chrome",
        "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox",
        "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave",
    ]

    public static func name(for bundleID: String) -> String? {
        names[bundleID]
    }
}

/// Turns "which apps are using the microphone right now" into call started / ended moments,
/// ignoring brief mic use and short drops (mute, a network hiccup).
public struct CallWatch: Sendable {
    public enum Event: Equatable, Sendable {
        case started(app: String)
        case ended(app: String)
    }

    static let startAfter: TimeInterval = 3
    static let endAfter: TimeInterval = 15

    private var candidateSince: Date?
    private var activeApp: String?
    private var silentSince: Date?

    public init() {}

    public var isInCall: Bool { activeApp != nil }

    public mutating func update(micApps bundleIDs: [String], at now: Date = Date()) -> Event? {
        let app = bundleIDs.lazy.compactMap(CallApps.name(for:)).first
        if let active = activeApp {
            if app != nil {
                silentSince = nil
                return nil
            }
            let since = silentSince ?? now
            silentSince = since
            guard now.timeIntervalSince(since) >= Self.endAfter else { return nil }
            activeApp = nil
            silentSince = nil
            candidateSince = nil
            return .ended(app: active)
        }
        guard let app else {
            candidateSince = nil
            return nil
        }
        let since = candidateSince ?? now
        candidateSince = since
        guard now.timeIntervalSince(since) >= Self.startAfter else { return nil }
        activeApp = app
        return .started(app: app)
    }
}
