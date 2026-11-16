import Foundation

/// A web browser people take calls in, and how Transkribe can see which meetings it has open.
public struct Browser: Equatable, Sendable {
    public enum Reading: Sendable {
        /// Lists every tab's address over Apple Events (Chrome's scripting dictionary).
        case chromiumScript
        /// Lists every tab's address over Apple Events (Safari's scripting dictionary).
        case safariScript
        /// No tab list to script; reads window titles (the front tab of each window) via Accessibility.
        case windowTitles
    }

    public let bundleID: String
    public let name: String
    public let reading: Reading

    /// Whether macOS asks "Transkribe wants to control <browser>" before tabs can be read.
    public var needsAutomation: Bool { reading != .windowTitles }
}

public enum Browsers {
    public static let all: [Browser] = [
        Browser(bundleID: "com.google.Chrome", name: "Chrome", reading: .chromiumScript),
        Browser(bundleID: "com.google.Chrome.beta", name: "Chrome Beta", reading: .chromiumScript),
        Browser(bundleID: "com.google.Chrome.dev", name: "Chrome Dev", reading: .chromiumScript),
        Browser(bundleID: "com.google.Chrome.canary", name: "Chrome Canary", reading: .chromiumScript),
        Browser(bundleID: "org.chromium.Chromium", name: "Chromium", reading: .chromiumScript),
        Browser(bundleID: "com.brave.Browser", name: "Brave", reading: .chromiumScript),
        Browser(bundleID: "com.brave.Browser.beta", name: "Brave Beta", reading: .chromiumScript),
        Browser(bundleID: "com.brave.Browser.nightly", name: "Brave Nightly", reading: .chromiumScript),
        Browser(bundleID: "com.microsoft.edgemac", name: "Edge", reading: .chromiumScript),
        Browser(bundleID: "com.microsoft.edgemac.Beta", name: "Edge Beta", reading: .chromiumScript),
        Browser(bundleID: "com.microsoft.edgemac.Dev", name: "Edge Dev", reading: .chromiumScript),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc", reading: .chromiumScript),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", reading: .chromiumScript),
        Browser(bundleID: "com.operasoftware.Opera", name: "Opera", reading: .chromiumScript),
        Browser(bundleID: "com.apple.Safari", name: "Safari", reading: .safariScript),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview", reading: .safariScript),
        Browser(bundleID: "org.mozilla.firefox", name: "Firefox", reading: .windowTitles),
        Browser(bundleID: "org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition", reading: .windowTitles),
        Browser(bundleID: "org.mozilla.nightly", name: "Firefox Nightly", reading: .windowTitles),
        Browser(bundleID: "app.zen-browser.zen", name: "Zen", reading: .windowTitles),
        Browser(bundleID: "company.thebrowser.dia", name: "Dia", reading: .windowTitles),
        Browser(bundleID: "com.kagi.kagimacOS", name: "Orion", reading: .windowTitles),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.bundleID, $0) })

    /// The browser a process belongs to, including its helpers ("com.google.Chrome.helper" is Chrome).
    public static func browser(for bundleID: String) -> Browser? {
        if let browser = byID[bundleID] { return browser }
        var parts = bundleID.split(separator: ".")
        while parts.count > 2 {
            parts.removeLast()
            if let browser = byID[parts.joined(separator: ".")] { return browser }
        }
        return nil
    }

    public static func isBrowser(name: String) -> Bool {
        all.contains { $0.name == name }
    }
}
