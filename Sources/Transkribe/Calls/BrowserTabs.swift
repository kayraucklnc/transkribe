import AppKit
import ApplicationServices
import TranskribeCore

/// Looks at the meetings open in a browser: every tab's address in Chrome-family browsers and
/// Safari (with the "control <browser>" permission), or each window's title in Firefox, Zen and
/// others (with Accessibility, which dictation already uses). It never asks for a permission or
/// starts a browser on its own; that happens only from the permission screen.
@MainActor
enum BrowserTabs {
    enum Access: Equatable {
        case allowed
        case notAsked
        case denied
        /// Apple Events can only be checked or asked for while the browser is open.
        case notRunning
    }

    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// The meetings open in `browser`, or nil when Transkribe can't tell (not allowed, not open).
    static func meetings(in browser: Browser) -> [BrowserMeeting]? {
        guard isRunning(browser) else { return nil }
        switch browser.reading {
        case .chromiumScript, .safariScript:
            guard automationStatus(browser.bundleID, ask: false) == .allowed, let urls = tabURLs(in: browser) else { return nil }
            return urls.compactMap(URL.init(string:)).compactMap(BrowserMeeting.from(url:))
        case .windowTitles:
            guard AXIsProcessTrusted() else { return nil }
            return windowTitles(of: browser).compactMap(BrowserMeeting.from(windowTitle:))
        }
    }

    /// Whether Transkribe may read `browser`'s tabs, without asking. macOS only answers while the
    /// browser is open, so a closed browser reports what it said last time.
    static func access(to browser: Browser) -> Access {
        guard browser.needsAutomation else { return AXIsProcessTrusted() ? .allowed : .notAsked }
        let status = automationStatus(browser.bundleID, ask: false)
        return remember(status, for: browser)
    }

    private static func remember(_ status: Access, for browser: Browser) -> Access {
        let key = "browserAutomationGranted.\(browser.bundleID)"
        switch status {
        case .allowed: UserDefaults.standard.set(true, forKey: key)
        case .denied: UserDefaults.standard.set(false, forKey: key)
        case .notAsked, .notRunning: break
        }
        if status == .notRunning, UserDefaults.standard.bool(forKey: key) { return .allowed }
        return status
    }

    /// Asks macOS for permission to read `browser`'s tabs. Opens the browser in the background
    /// first if it isn't running, since macOS only asks about an open app.
    static func requestAccess(to browser: Browser) async -> Access {
        guard browser.needsAutomation else {
            TextInserter.requestTrust()
            return access(to: browser)
        }
        if !isRunning(browser), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            for _ in 0..<20 where !isRunning(browser) { try? await Task.sleep(for: .milliseconds(250)) }
        }
        let bundleID = browser.bundleID
        // The system prompt blocks until answered, so wait for it off the main thread.
        let status = await Task.detached { automationStatus(bundleID, ask: true) }.value
        return remember(status, for: browser)
    }

    static func isInstalled(_ browser: Browser) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil
    }

    static func isRunning(_ browser: Browser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    /// The browser that opens web links on this Mac.
    static var defaultBrowser: Browser? {
        guard let probe = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let bundleID = Bundle(url: app)?.bundleIdentifier else { return nil }
        return Browsers.browser(for: bundleID)
    }

    // MARK: - Apple Events

    /// Blocks while the system prompt is up when `ask` is true, so call that off the main thread.
    nonisolated private static func automationStatus(_ bundleID: String, ask: Bool) -> Access {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return .denied }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound): return .notRunning
        default: return .denied
        }
    }

    private static func tabURLs(in browser: Browser) -> [String]? {
        // Both dictionaries answer "URL of every tab of every window" with a list per window.
        let source = "tell application id \"\(browser.bundleID)\" to get URL of every tab of every window"
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }
        return flatten(result)
    }

    private static func flatten(_ descriptor: NSAppleEventDescriptor) -> [String] {
        guard descriptor.numberOfItems > 0 else { return descriptor.stringValue.map { [$0] } ?? [] }
        return (1...descriptor.numberOfItems).flatMap { index in
            descriptor.atIndex(index).map(flatten) ?? []
        }
    }

    // MARK: - Accessibility

    private static func windowTitles(of browser: Browser) -> [String] {
        NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).flatMap { app -> [String] in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var windows: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
                  let list = windows as? [AXUIElement] else { return [] }
            return list.compactMap { window in
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return nil }
                return title as? String
            }
        }
    }
}
