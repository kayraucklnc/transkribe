import Foundation

/// Apps people take calls in, by bundle identifier. Browsers (for Meet and other web calls) come from `Browsers`.
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
    ]

    /// Also matches an app's helper processes ("com.google.Chrome.helper" is Chrome): browsers
    /// often capture the microphone from a helper, not the main app.
    public static func name(for bundleID: String) -> String? {
        if let browser = Browsers.browser(for: bundleID) { return browser.name }
        if let name = names[bundleID] { return name }
        var parts = bundleID.split(separator: ".")
        while parts.count > 2 {
            parts.removeLast()
            if let name = names[parts.joined(separator: ".")] { return name }
        }
        return nil
    }
}

/// Turns "which apps are using the microphone right now" into call started / ended moments,
/// ignoring brief mic use and short drops (a device switch, a network hiccup). Meeting apps keep
/// the mic open while you're muted (that's how they warn "you're muted"), so mute isn't a drop.
public struct CallWatch: Sendable {
    public enum Event: Equatable, Sendable {
        case started(app: String)
        case ended(app: String)
    }

    static let startAfter: TimeInterval = 3
    static let endAfter: TimeInterval = 15
    /// A browser call whose meeting tab is still open gets longer to pick the mic back up.
    static let endAfterWithMeetingOpen: TimeInterval = 45

    private var candidateSince: Date?
    private var activeApp: String?
    /// The process holding the mic for the call, to know which browser to look in.
    public private(set) var activeBundleID: String?
    private var silentSince: Date?
    /// The call's meeting tab was seen open, so its disappearing means you left.
    private var sawMeetingOpen = false
    private var meetingGoneSince: Date?

    public init() {}

    public var isInCall: Bool { activeApp != nil }

    /// `meetingOpen` is whether the call's browser still has a meeting tab open (nil when unknown
    /// or not a browser call).
    public mutating func update(micApps bundleIDs: [String], meetingOpen: Bool? = nil, at now: Date = Date()) -> Event? {
        let match = bundleIDs.lazy.compactMap { id in CallApps.name(for: id).map { (id, $0) } }.first
        if let active = activeApp {
            return updateCall(active, micApps: bundleIDs, meetingOpen: meetingOpen, at: now)
        }
        let app = match?.1
        guard let app else {
            candidateSince = nil
            return nil
        }
        let since = candidateSince ?? now
        candidateSince = since
        guard now.timeIntervalSince(since) >= Self.startAfter else { return nil }
        activeApp = app
        activeBundleID = match?.0
        return .started(app: app)
    }

    /// Only the app that started the call counts: another call app on the mic (Slack, a second
    /// browser) doesn't keep it going. A browser call also ends once its meeting tab is gone,
    /// even if the browser keeps the mic for something else.
    private mutating func updateCall(_ active: String, micApps bundleIDs: [String], meetingOpen: Bool?, at now: Date) -> Event? {
        if meetingOpen == true { sawMeetingOpen = true }
        meetingGoneSince = sawMeetingOpen && meetingOpen == false ? (meetingGoneSince ?? now) : nil
        if let gone = meetingGoneSince, now.timeIntervalSince(gone) >= Self.endAfter {
            return endCall(active)
        }
        if bundleIDs.contains(where: { CallApps.name(for: $0) == active }) {
            silentSince = nil
            return nil
        }
        let since = silentSince ?? now
        silentSince = since
        let grace = meetingOpen == true ? Self.endAfterWithMeetingOpen : Self.endAfter
        guard now.timeIntervalSince(since) >= grace else { return nil }
        return endCall(active)
    }

    private mutating func endCall(_ active: String) -> Event {
        activeApp = nil
        activeBundleID = nil
        silentSince = nil
        candidateSince = nil
        sawMeetingOpen = false
        meetingGoneSince = nil
        return .ended(app: active)
    }
}
