import AppKit
import Observation
import TranskribeCore

/// Notices when a call starts (Zoom, Meet, FaceTime…), offers to record it, and stops the
/// recording it started when the call ends. The offer shows in the notch island (`NotchHUD`).
@Observable @MainActor
final class CallMonitor {
    /// The app of a call that just started, while the island asks whether to record it.
    private(set) var prompt: String?
    /// The call's mic went quiet before the meeting's planned end: recording continues until
    /// this time unless you stop it (see `CallEndPolicy`). The island asks "Call over?".
    private(set) var keepsRecordingUntil: Date?
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
    /// The calendar meeting the current recording is for: its end is when a quiet mic may stop it.
    private var recordedMeeting: CalendarMeeting?
    /// How long after Join the call may take to pick up the mic (a lobby, a Zoom update).
    private static let joinWindow: TimeInterval = 15 * 60
    /// The calendar meeting whose link is open in the browser that started the call being offered.
    private var promptMeeting: CalendarMeeting?
    /// The process that held the mic for the current call, kept after the mic goes quiet so a
    /// recording waiting for the planned end can still see the meeting tab close.
    private var callBrowserID: String?
    /// When the current call picked up the mic, to tell whether a recording you started is for it.
    private var callStartedAt: Date?

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
        // While a browser call runs, an open meeting tab gives the mic longer to come back, and a
        // closed one ends it. After a quiet mic, a closed tab still stops a recording that's waiting.
        let watchesBrowser = watch.isInCall || keepsRecordingUntil != nil
        let meetingOpen = watchesBrowser ? browserMeetings().map { !$0.isEmpty } : nil
        if recordingForCall, !model.isRecording, model.recordingState == .idle {
            finishCall() // stopped by hand
        }
        adoptRecordingStartedByHand()
        switch watch.update(micApps: MicUsage.bundleIDs(), meetingOpen: meetingOpen) {
        case .started(let app)?:
            callStartedAt = Date()
            callBrowserID = watch.activeBundleID
            if keepsRecordingUntil != nil {
                keepsRecordingUntil = nil // the call came back; carry on
                return
            }
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
            callStartedAt = nil
            dismiss()
            guard recordingForCall, model.isRecording, stopsWithCall || recordedMeeting != nil else {
                finishCall()
                return
            }
            switch CallEndPolicy.decide(now: Date(), scheduledEnd: recordedMeeting?.end, leftMeeting: meetingOpen == false) {
            case .stop: stopForCallEnd()
            case .keepUntil(let end): keepsRecordingUntil = end
            }
        case nil:
            if let end = keepsRecordingUntil,
               CallEndPolicy.stopsWhileWaiting(now: Date(), until: end, meetingOpen: meetingOpen) {
                stopForCallEnd()
            }
            if let joined = joinedMeeting, Date() > joined.until {
                joinedMeeting = nil
                restart()
            }
        }
    }

    /// A recording you started yourself during the call (or just before joining it) is the call's
    /// too: with "Stop recording when the call ends" on, the call's end stops it.
    private func adoptRecordingStartedByHand() {
        guard stopsWithCall, !recordingForCall, watch.isInCall, let callStartedAt,
              case .recording(let since) = model.recordingState,
              CallEndPolicy.belongsToCall(recordingStartedAt: since, callStartedAt: callStartedAt) else { return }
        recordingForCall = true
        // As from the card: during a calendar meeting, a quiet mic waits for the planned end.
        recordedMeeting = CalendarTitles.meetingWithLinkOnNow()
    }

    /// From the island: the call is over, stop now.
    func stopNow() {
        stopForCallEnd()
    }

    /// From the island: keep recording; you'll stop it yourself.
    func keepRecording() {
        finishCall()
    }

    private func stopForCallEnd() {
        if model.isRecording {
            model.stopRecording()
            model.showToast("Call ended · recording saved")
        }
        finishCall()
    }

    /// Forgets the call; the recording (if any) now runs until you stop it.
    private func finishCall() {
        recordingForCall = false
        recordedMeeting = nil
        keepsRecordingUntil = nil
        callBrowserID = nil
        restart()
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
        // A call during a calendar meeting keeps recording through quiet stretches until it's planned to end.
        recordedMeeting = CalendarTitles.meetingWithLinkOnNow()
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

    /// The calendar meeting the running recording is for, if any.
    var currentMeetingID: CalendarMeeting.ID? { recordedMeeting?.id }

    /// Whether the recording running now is for `meeting`.
    func isRecording(_ meeting: CalendarMeeting) -> Bool {
        recordedMeeting?.id == meeting.id
    }

    private func record(_ meeting: CalendarMeeting) {
        dismiss()
        joinedMeeting = nil
        model.recordingSource = .both
        model.startRecording(title: meeting.title)
        recordingForCall = true
        recordedMeeting = meeting
    }

    func dismiss() {
        promptTask?.cancel()
        prompt = nil
        promptMeeting = nil
    }

    /// Meetings open in the browser holding the call's mic (or that held it, while a recording waits
    /// for the planned end); nil if it isn't a browser or can't be read.
    private func browserMeetings() -> [BrowserMeeting]? {
        guard let id = watch.activeBundleID ?? callBrowserID, let browser = Browsers.browser(for: id) else { return nil }
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
