import AppKit
import Observation
import SwiftUI
import TranskribeCore

/// A small black island that grows out of the MacBook notch (or the top center of the screen):
/// a red dot and a timer while recording, a clear "Recording" / "Saved" moment at start and stop,
/// meeting reminders with a Join button, and the "record this call?" offer. Screen sharing doesn't see it.
@Observable @MainActor
final class NotchHUD {
    enum Announcement: Equatable {
        case started(title: String)
        case stopped(title: String, duration: TimeInterval)
    }

    enum Mode: Equatable {
        case hidden
        case pill
        case recordingDetails
        case announcement(Announcement)
        case reminder(MeetingReminder)
        /// A call started in this app; offer to record it.
        case callPrompt(app: String)
        /// The call's mic went quiet before the meeting's planned end; still recording until then.
        case callSeemsOver(until: Date)
        /// Mid-call, one line: "Wrap up · Design review in 5 min".
        case wrapUp(CalendarMeeting)

        var showsCard: Bool {
            switch self {
            case .hidden, .pill: false
            case .recordingDetails, .announcement, .reminder, .callPrompt, .callSeemsOver, .wrapUp: true
            }
        }
    }

    var showsRecording: Bool {
        didSet { UserDefaults.standard.set(showsRecording, forKey: Self.showsKey); layout() }
    }
    var playsSounds: Bool {
        didSet { HUDSounds.isEnabled = playsSounds }
    }

    private(set) var announcement: Announcement?
    private(set) var geometry = NotchGeometry.current()
    /// The pill was clicked open to show the title and a Stop button.
    var isExpanded = false {
        didSet { layout(); scheduleCollapse() }
    }
    var isHovering = false {
        didSet { if !isHovering { scheduleCollapse() } }
    }

    let model: AppModel
    let reminders: MeetingReminders
    let calls: CallMonitor

    static let announcementDuration: Duration = .seconds(2.8)
    static let detailsDuration: Duration = .seconds(6)
    private static let showsKey = "showsNotchRecordingIndicator"

    private let panel = HUDPanel()
    private var lastState: AppModel.RecordingState = .idle
    private var recordingTitle = ""
    private var announcementTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel, reminders: MeetingReminders, calls: CallMonitor) {
        self.model = model
        self.reminders = reminders
        self.calls = calls
        showsRecording = UserDefaults.standard.object(forKey: Self.showsKey) as? Bool ?? true
        playsSounds = HUDSounds.isEnabled
    }

    func start() {
        panel.setContent(NotchHUDView(hud: self))
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.geometry = NotchGeometry.current()
                self.layout()
            }
        }
        observe()
    }

    var mode: Mode {
        if let announcement, showsRecording { return .announcement(announcement) }
        if let until = calls.keepsRecordingUntil, isRecording { return .callSeemsOver(until: until) }
        if let app = calls.prompt { return .callPrompt(app: app) }
        if let reminder = reminders.current { return .reminder(reminder) }
        if let next = reminders.nudge, isRecording { return .wrapUp(next) }
        guard isRecording, showsRecording else { return .hidden }
        return isExpanded ? .recordingDetails : .pill
    }

    var isRecording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }

    var recordingSince: Date? {
        if case .recording(let since) = model.recordingState { return since }
        return nil
    }

    var liveTitle: String {
        model.liveRecordingID.flatMap { model.transcript($0)?.title } ?? recordingTitle
    }

    func openRecording() {
        isExpanded = false
        model.selection = nil
        MainWindow.show()
    }

    func stopRecording() {
        isExpanded = false
        model.stopRecording()
    }

    // MARK: - Following the recording

    private func observe() {
        withObservationTracking {
            _ = model.recordingState
            _ = reminders.current
            _ = calls.prompt
            _ = calls.keepsRecordingUntil
            _ = reminders.nudge
        } onChange: { [weak self] in
            // Fires before the change lands; re-reading on the next turn sees the new value.
            Task { @MainActor in self?.observe() }
        }
        recordingStateChanged()
    }

    private func recordingStateChanged() {
        let state = model.recordingState
        defer { lastState = state }
        switch (lastState, state) {
        case (.recording, .recording), (.idle, .idle), (.starting, .starting), (.stopping, .stopping):
            break
        case (_, .recording):
            recordingTitle = liveTitle
            HUDSounds.play(.start)
            announce(.started(title: recordingTitle))
        case (.recording(let since), _):
            isExpanded = false
            HUDSounds.play(.stop)
            announce(.stopped(title: recordingTitle, duration: Date().timeIntervalSince(since)))
        default:
            break
        }
        layout()
    }

    private func announce(_ value: Announcement) {
        announcement = value
        announcementTask?.cancel()
        announcementTask = Task { [weak self] in
            try? await Task.sleep(for: Self.announcementDuration)
            guard !Task.isCancelled, let self else { return }
            self.announcement = nil
            self.layout()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        guard isExpanded else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.detailsDuration)
            guard !Task.isCancelled, let self, !self.isHovering else { return }
            self.isExpanded = false
        }
    }

    // MARK: - Window

    /// Grows the window right away and shrinks it once the island has animated smaller,
    /// so it never cuts the animation off and never covers more of the screen than it needs.
    private func layout() {
        let mode = mode
        let target = geometry.size(for: mode)
        resizeTask?.cancel()
        if mode == .hidden {
            resizeTask = Task { [weak self] in
                try? await Task.sleep(for: IslandMotion.restTime)
                guard !Task.isCancelled, let self, self.mode == .hidden else { return }
                self.panel.hide()
            }
            return
        }
        let current = panel.isVisible ? panel.frame.size : .zero
        let grown = CGSize(width: max(target.width, current.width), height: max(target.height, current.height))
        panel.show(frame: geometry.frame(for: grown))
        guard grown != target else { return }
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: IslandMotion.restTime)
            guard !Task.isCancelled, let self else { return }
            self.panel.show(frame: self.geometry.frame(for: target))
        }
    }
}

/// Where the notch is on the screen that has one (or the top center of the main screen).
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    /// 0 on screens without a notch.
    var notchWidth: CGFloat
    /// The notch's height, or the menu bar's on screens without one.
    var topHeight: CGFloat
    var centerX: CGFloat

    var hasNotch: Bool { notchWidth > 0 }

    static let wing: CGFloat = 44
    static let cardWidth: CGFloat = 360
    static let cardHeight: CGFloat = 64
    /// A one-line nudge: less island, less distraction.
    static let slimHeight: CGFloat = 34

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NotchGeometry(screenFrame: .zero, notchWidth: 0, topHeight: 24, centerX: 0)
        }
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notch = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame, notchWidth: notch, topHeight: screen.safeAreaInsets.top,
                                 centerX: frame.minX + left.width + notch / 2)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(screenFrame: frame, notchWidth: 0,
                             topHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness, centerX: frame.midX)
    }

    func size(for mode: NotchHUD.Mode) -> CGSize {
        switch mode {
        case .hidden:
            return CGSize(width: notchWidth, height: topHeight)
        case .pill:
            return CGSize(width: hasNotch ? notchWidth + 2 * Self.wing : 2 * Self.wing + 12, height: topHeight)
        case .wrapUp:
            return CGSize(width: max(Self.cardWidth, notchWidth + 2 * Self.wing), height: topHeight + Self.slimHeight)
        case .recordingDetails, .announcement, .reminder, .callPrompt, .callSeemsOver:
            return CGSize(width: max(Self.cardWidth, notchWidth + 2 * Self.wing), height: topHeight + Self.cardHeight)
        }
    }

    func frame(for size: CGSize) -> CGRect {
        CGRect(x: (centerX - size.width / 2).rounded(), y: screenFrame.maxY - size.height,
               width: size.width.rounded(), height: size.height.rounded())
    }
}

/// A borderless panel above the menu bar that never takes focus and is left out of screen sharing.
@MainActor
private final class HUDPanel {
    private let panel: NSPanel = {
        let panel = HUDWindow(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        // Screen sharing and screenshots leave this window out.
        panel.sharingType = .none
        return panel
    }()

    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }

    func setContent<Content: View>(_ view: Content) {
        panel.setSwiftUIContent(view)
    }

    func show(frame: CGRect) {
        panel.setFrame(frame, display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class HUDWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Panels are normally kept below the menu bar; this one sits in the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The start, stop and reminder chimes, unless turned off in Settings.
@MainActor
enum HUDSounds {
    private static let key = "playsRecordingSounds"
    private static var sounds: [Chime: NSSound] = [:]

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func play(_ chime: Chime) {
        guard isEnabled else { return }
        guard let sound = sounds[chime] ?? NSSound(data: chime.wav()) else { return }
        sounds[chime] = sound
        sound.stop()
        sound.play()
    }
}

/// Brings the main window forward from outside SwiftUI (the notch island, a reminder).
@MainActor
enum MainWindow {
    /// Set by a SwiftUI view that can open scenes, for when the window was closed.
    static var opener: (() -> Void)?

    static func show() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            opener?()
        }
    }
}
