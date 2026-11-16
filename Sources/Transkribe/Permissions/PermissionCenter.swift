import AppKit
import AVFoundation
import EventKit
import Observation
import SwiftUI
import TranskribeCore

/// Every permission Transkribe uses, whether each is granted, and how to ask for it. Setup and
/// the launch check both use it: the app doesn't open without the microphone and call audio;
/// the rest (calendar, Accessibility, browser tabs) are optional and only turn features on.
@Observable @MainActor
final class PermissionCenter {
    enum Kind: Hashable {
        case microphone
        case systemAudio
        case calendar
        case accessibility
        /// Reading meeting tabs in a browser that answers Apple Events (Chrome, Brave, Arc, Safari…).
        case browser(bundleID: String)
    }

    enum State: Equatable {
        case granted
        case notAsked
        /// Turned off, or asked before: only System Settings can change it now.
        case denied
        /// Allowed in System Settings, but macOS applies it only after Transkribe reopens.
        case needsReopen
    }

    struct Item: Identifiable, Equatable {
        let kind: Kind
        let symbol: String
        let title: String
        let detail: String
        let tint: Color
        var state: State
        var id: Kind { kind }

        /// Recording needs these; everything else adds features.
        var isRequired: Bool {
            kind == .microphone || kind == .systemAudio
        }
    }

    private(set) var items: [Item] = []

    /// The app can be used: every required permission is allowed.
    var requiredGranted: Bool { items.filter(\.isRequired).allSatisfy { $0.state == .granted } }
    /// During setup, a permission that only needs a reopen is fine: it's finished after setup.
    var readyForSetup: Bool {
        items.filter(\.isRequired).allSatisfy { $0.state == .granted || $0.state == .needsReopen }
    }

    /// The permissions page opened after setup and the person hasn't moved on yet. Saved, so
    /// reopening Transkribe (which macOS asks for after Screen Recording) comes back to it.
    private(set) var isReviewing = SetupProgress.load().reviewingPermissions

    /// Whether the permissions page covers the app once setup is done.
    func showsGate(completedOnboarding: Bool) -> Bool {
        SetupProgress(onboardingStep: nil, reviewingPermissions: isReviewing)
            .showsPermissions(completedOnboarding: completedOnboarding, requiredGranted: requiredGranted)
    }

    func beginReview() { setReviewing(true) }
    func finishReview() { setReviewing(false) }

    private func setReviewing(_ reviewing: Bool) {
        guard reviewing != isReviewing else { return }
        isReviewing = reviewing
        SetupProgress.update { $0.reviewingPermissions = reviewing }
    }

    private static let askedKey = "askedPermissions"
    private var asked: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.askedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.askedKey) }
    }
    private var activeObserver: NSObjectProtocol?

    init() {
        refresh()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Re-reads every permission; they change in System Settings, outside the app.
    func refresh() {
        let updated = kinds.map(item)
        if updated != items { items = updated }
    }

    func request(_ kind: Kind) async {
        let firstTime = !asked.contains(key(kind))
        asked.insert(key(kind))
        switch kind {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                openSettings(kind)
            }
        case .systemAudio:
            // The first request shows macOS's own prompt; after that only System Settings can turn it on.
            if firstTime { _ = CGRequestScreenCaptureAccess() } else { openSettings(kind) }
        case .calendar:
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = await CalendarTitles.requestAccess()
            } else {
                openSettings(kind)
            }
        case .accessibility:
            TextInserter.requestTrust()
            if !firstTime { openSettings(kind) }
        case .browser(let bundleID):
            guard let browser = Browsers.browser(for: bundleID) else { break }
            if await BrowserTabs.requestAccess(to: browser) == .denied { openSettings(kind) }
        }
        refresh()
    }

    func openSettings(_ kind: Kind) {
        let pane = switch kind {
        case .microphone: "Privacy_Microphone"
        case .systemAudio: "Privacy_ScreenCapture"
        case .calendar: "Privacy_Calendars"
        case .accessibility: "Privacy_Accessibility"
        case .browser: "Privacy_Automation"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts a fresh copy of Transkribe and quits this one, so macOS applies Screen Recording.
    func reopen() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: - Reading

    private var kinds: [Kind] {
        var kinds: [Kind] = [.microphone, .systemAudio, .calendar, .accessibility]
        // The browser links open in; others can be allowed from Settings › Calls.
        if let browser = BrowserTabs.defaultBrowser, browser.needsAutomation {
            kinds.append(.browser(bundleID: browser.bundleID))
        }
        return kinds
    }

    private func item(_ kind: Kind) -> Item {
        switch kind {
        case .microphone:
            return Item(kind: kind, symbol: "mic.fill", title: "Your microphone",
                        detail: "To record what you and people in the room say.", tint: Theme.record,
                        state: state(AVCaptureDevice.authorizationStatus(for: .audio)))
        case .systemAudio:
            let granted = CGPreflightScreenCaptureAccess()
            return Item(kind: kind, symbol: "speaker.wave.2.fill", title: "Sound from calls and apps",
                        detail: "To capture the other side of Zoom, Meet or FaceTime calls. Your screen is never recorded.",
                        tint: .blue,
                        state: granted ? .granted : (asked.contains(key(kind)) ? .needsReopen : .notAsked))
        case .calendar:
            let status = EKEventStore.authorizationStatus(for: .event)
            return Item(kind: kind, symbol: "calendar", title: "Your calendar",
                        detail: "For meeting reminders, one-click Join, and naming recordings after the meeting.",
                        tint: .orange,
                        state: status == .fullAccess ? .granted : (status == .notDetermined ? .notAsked : .denied))
        case .accessibility:
            return Item(kind: kind, symbol: "accessibility", title: "Accessibility",
                        detail: "Lets dictation type into other apps, and lets Transkribe see meeting windows in Firefox, Zen and other browsers.",
                        tint: .purple,
                        state: AXIsProcessTrusted() ? .granted : (asked.contains(key(kind)) ? .denied : .notAsked))
        case .browser(let bundleID):
            let browser = Browsers.browser(for: bundleID)
            let name = browser?.name ?? "your browser"
            return Item(kind: kind, symbol: "globe", title: "See meeting tabs in \(name)",
                        detail: "So recording follows the real meeting, even when it runs late. Transkribe only looks for Meet, Zoom and Teams links and keeps nothing.",
                        tint: .teal, state: browserState(browser))
        }
    }

    private func state(_ status: AVAuthorizationStatus) -> State {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    private func browserState(_ browser: Browser?) -> State {
        guard let browser else { return .granted }
        switch BrowserTabs.access(to: browser) {
        case .allowed: return .granted
        case .denied: return .denied
        case .notAsked, .notRunning: return .notAsked
        }
    }

    private func key(_ kind: Kind) -> String {
        switch kind {
        case .microphone: "microphone"
        case .systemAudio: "systemAudio"
        case .calendar: "calendar"
        case .accessibility: "accessibility"
        case .browser(let id): "browser:\(id)"
        }
    }

}
