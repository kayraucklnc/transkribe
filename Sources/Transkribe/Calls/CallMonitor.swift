import AppKit
import Observation
import TranskribeCore

/// Notices when a call starts (Zoom, Meet, FaceTime…), offers to record it, and stops the
/// recording it started when the call ends. The offer shows in the notch island (`NotchHUD`).
@Observable @MainActor
final class CallMonitor {
    /// The app of a call that just started, while the island asks whether to record it.
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
    /// Records without asking when a call starts during a calendar meeting that has a call link,
    /// however you joined it. Off by default: nothing is recorded unless you choose to.
    var recordsCalendarMeetings: Bool {
        didSet { UserDefaults.standard.set(recordsCalendarMeetings, forKey: Self.autoKey); restart() }
    }

    private static let offerKey = "offersToRecordCalls"
    private static let stopKey = "stopsRecordingWithCall"
    private static let calendarKey = "namesRecordingsFromCalendar"
    private static let autoKey = "recordsCalendarMeetingsAutomatically"
    private static let promptDuration: Duration = .seconds(25)

    private unowned let model: AppModel
    private var watch = CallWatch()
    private var timer: Timer?
    private var promptTask: Task<Void, Never>?
    /// The recording this monitor started for the current call, to stop when it ends.
    private var recordingForCall = false
    /// A meeting joined from its reminder: the next call that starts is recorded under its name.
    private var joinedMeeting: (meeting: CalendarMeeting, until: Date)?
    /// The meeting the current recording is for, if it was started for one.
    private var recordedMeetingID: CalendarMeeting.ID?
    /// How long after Join the call may take to pick up the mic (a lobby, a Zoom update).
    private static let joinWindow: TimeInterval = 15 * 60
    /// The calendar meeting whose link is open in the browser that started the call being offered.
    private var promptMeeting: CalendarMeeting?

    init(model: AppModel) {
        self.model = model
        let defaults = UserDefaults.standard
        offersToRecord = defaults.object(forKey: Self.offerKey) as? Bool ?? true
        stopsWithCall = defaults.object(forKey: Self.stopKey) as? Bool ?? true
        usesCalendar = defaults.bool(forKey: Self.calendarKey)
        recordsCalendarMeetings = defaults.bool(forKey: Self.autoKey)
    }

    func start() {
        restart()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        guard offersToRecord || recordsCalendarMeetings || joinedMeeting != nil || recordingForCall else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        // While a browser call runs, an open meeting tab gives the mic longer to come back.
        let meetingOpen = watch.isInCall ? browserMeetings().map { !$0.isEmpty } : nil
        switch watch.update(micApps: MicUsage.bundleIDs(), meetingOpen: meetingOpen) {
        case .started(let app)?:
            guard !model.isRecording, model.settings.completedOnboarding else { return }
            let tab = browserMeetings()?.first
            let scheduled = tab.flatMap(CalendarTitles.meeting(matching:))
            if let joined = joinedMeeting, Date() <= joined.until {
                record(joined.meeting)
            } else if recordsCalendarMeetings, let meeting = scheduled ?? CalendarTitles.meetingWithLinkOnNow() {
                record(meeting)
            } else if offersToRecord {
                promptMeeting = scheduled
                show(prompt: tab?.service.rawValue ?? app)
            }
        case .ended?:
            dismiss()
            // The call's real end, which may be well past the calendar's end time.
            if recordingForCall, stopsWithCall || recordedMeetingID != nil, model.isRecording {
                model.stopRecording()
                model.showToast("Call ended · recording saved")
            }
            recordingForCall = false
            recordedMeetingID = nil
            restart()
        case nil:
            if let joined = joinedMeeting, Date() > joined.until {
                joinedMeeting = nil
                restart()
            }
        }
    }

    func recordCall() {
        if let meeting = promptMeeting {
            record(meeting)
            return
        }
        dismiss()
        let event = usesCalendar ? CalendarTitles.currentEvent() : nil
        model.recordingSource = .both
        model.startRecording(title: event?.title)
        recordingForCall = true
    }

    /// Records the next call that starts as `meeting`, without asking. If a call app already has
    /// the mic (you were in the lobby, or joined before clicking), recording starts now.
    func recordNextCall(as meeting: CalendarMeeting) {
        guard !model.isRecording else { return }
        if watch.isInCall {
            record(meeting)
        } else {
            joinedMeeting = (meeting, Date().addingTimeInterval(Self.joinWindow))
            restart()
        }
    }

    /// Whether the recording running now is for `meeting`.
    func isRecording(_ meeting: CalendarMeeting) -> Bool {
        recordedMeetingID == meeting.id
    }

    private func record(_ meeting: CalendarMeeting) {
        dismiss()
        joinedMeeting = nil
        model.recordingSource = .both
        model.startRecording(title: meeting.title)
        recordingForCall = true
        recordedMeetingID = meeting.id
    }

    func dismiss() {
        promptTask?.cancel()
        prompt = nil
        promptMeeting = nil
    }

    /// Meetings open in the browser holding the call's mic; nil if it isn't a browser or can't be read.
    private func browserMeetings() -> [BrowserMeeting]? {
        guard let id = watch.activeBundleID, let browser = Browsers.browser(for: id) else { return nil }
        return BrowserTabs.meetings(in: browser)
    }

    private func show(prompt app: String) {
        prompt = app
        HUDSounds.play(.reminder)
        promptTask?.cancel()
        promptTask = Task {
            try? await Task.sleep(for: Self.promptDuration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
