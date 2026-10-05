import AppKit
import Observation
import SwiftUI
import TranskribeCore

/// Notices when a call starts (Zoom, Meet, FaceTime…), offers to record it, and stops the
/// recording it started when the call ends.
@Observable @MainActor
final class CallMonitor {
    private(set) var prompt: String?
    var offersToRecord: Bool {
        didSet { UserDefaults.standard.set(offersToRecord, forKey: Self.offerKey); restart() }
    }
    var stopsWithCall: Bool {
        didSet { UserDefaults.standard.set(stopsWithCall, forKey: Self.stopKey) }
    }
    var usesCalendar: Bool {
        didSet { UserDefaults.standard.set(usesCalendar, forKey: Self.calendarKey) }
    }

    private static let offerKey = "offersToRecordCalls"
    private static let stopKey = "stopsRecordingWithCall"
    private static let calendarKey = "namesRecordingsFromCalendar"
    private static let promptDuration: Duration = .seconds(25)

    private unowned let model: AppModel
    private var watch = CallWatch()
    private var timer: Timer?
    private var promptTask: Task<Void, Never>?
    /// The recording this monitor started for the current call, to stop when it ends.
    private var recordingForCall = false
    private let panel = CallPromptPanel()

    init(model: AppModel) {
        self.model = model
        let defaults = UserDefaults.standard
        offersToRecord = defaults.object(forKey: Self.offerKey) as? Bool ?? true
        stopsWithCall = defaults.object(forKey: Self.stopKey) as? Bool ?? true
        usesCalendar = defaults.bool(forKey: Self.calendarKey)
    }

    func start() {
        restart()
    }

    private func restart() {
        timer?.invalidate()
        guard offersToRecord else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        switch watch.update(micApps: MicUsage.bundleIDs()) {
        case .started(let app)?:
            guard !model.isRecording, model.settings.completedOnboarding else { return }
            show(prompt: app)
        case .ended?:
            dismiss()
            if recordingForCall, stopsWithCall, model.isRecording {
                model.stopRecording()
                model.showToast("Call ended · recording saved")
            }
            recordingForCall = false
        case nil:
            break
        }
    }

    func recordCall() {
        dismiss()
        let event = usesCalendar ? CalendarTitles.currentEvent() : nil
        model.recordingSource = .both
        model.startRecording(title: event?.title)
        recordingForCall = true
    }

    func dismiss() {
        promptTask?.cancel()
        prompt = nil
        panel.hide()
    }

    private func show(prompt app: String) {
        prompt = app
        panel.show(monitor: self)
        NSSound(named: "Pop")?.play()
        promptTask?.cancel()
        promptTask = Task {
            try? await Task.sleep(for: Self.promptDuration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

/// A small card at the top right of the screen, like a notification, that doesn't take focus.
@MainActor
private final class CallPromptPanel {
    private var panel: NSPanel?

    func show(monitor: CallMonitor) {
        let panel = panel ?? make(monitor: monitor)
        self.panel = panel
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 12, y: frame.maxY - panel.frame.height - 8))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        let panel = panel
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            panel?.orderOut(nil)
        }
    }

    private func make(monitor: CallMonitor) -> NSPanel {
        let panel = NonActivatingPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
                                       styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: CallPromptCard(monitor: monitor))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct CallPromptCard: View {
    let monitor: CallMonitor

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let app = monitor.prompt {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.record.opacity(0.18)).frame(width: 44, height: 44)
                        Circle().fill(Theme.record).frame(width: 18, height: 18)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(app) call").font(.system(size: 14, weight: .semibold))
                        Text("Record both sides and get a transcript?")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Record", action: monitor.recordCall)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.record)
                        .controlSize(.large)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .overlay(alignment: .topLeading) {
                    Button(action: monitor.dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .help("Not this time")
                }
                .padding(10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: monitor.prompt)
    }
}
