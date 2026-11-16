import AppKit
import Observation
import TranskribeCore

/// Reminds you about calendar meetings at the times you choose ("10 min before", "5 min before"…)
/// with a card by the notch. Join opens the call and records it once the call picks up the mic.
@Observable @MainActor
final class MeetingReminders {
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey); restart() }
    }
    /// Minutes before a meeting to remind, latest last. 0 is "at start".
    var minutes: [Int] {
        didSet {
            UserDefaults.standard.set(minutes, forKey: Self.minutesKey)
            schedule.setMinutes(minutes)
        }
    }
    var recordsWhenJoining: Bool {
        didSet { UserDefaults.standard.set(recordsWhenJoining, forKey: Self.recordKey) }
    }
    /// While you're in a call, how long before the next meeting to nudge you to wrap up. 0 is off.
    var wrapUpMinutes: Int {
        didSet {
            UserDefaults.standard.set(wrapUpMinutes, forKey: Self.wrapUpKey)
            wrapUp.minutes = wrapUpMinutes
            restart()
        }
    }

    /// The reminder on screen now.
    private(set) var current: MeetingReminder?
    /// The next meeting today, for Settings ("Next: Weekly sync in 40 min").
    private(set) var next: CalendarMeeting?
    /// A one-line "wrap up, <next meeting> in 5 min" under the notch, while you're in a call.
    private(set) var nudge: CalendarMeeting?
    /// The meeting you were nudged about, until it starts: the island's timer stays orange.
    private(set) var upNext: CalendarMeeting?

    private static let enabledKey = "remindsAboutMeetings"
    private static let minutesKey = "meetingReminderMinutes"
    private static let recordKey = "recordsJoinedMeetings"
    private static let wrapUpKey = "wrapUpNudgeMinutes"
    /// A nudge is a glance, not a card: it slides away on its own.
    static let nudgeDuration: Duration = .seconds(8)
    /// A reminder card goes away on its own this long after the meeting starts.
    private static let cardLifetime: TimeInterval = 5 * 60
    private static let refreshInterval: TimeInterval = 60

    private unowned let model: AppModel
    private unowned let calls: CallMonitor
    private var schedule: MeetingReminderSchedule
    private var wrapUp: WrapUpSchedule
    private var nudgeTask: Task<Void, Never>?
    private var meetings: [CalendarMeeting] = []
    private var refreshedAt: Date = .distantPast
    private var timer: Timer?
    private var changesTask: Task<Void, Never>?

    init(model: AppModel, calls: CallMonitor) {
        self.model = model
        self.calls = calls
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        recordsWhenJoining = defaults.object(forKey: Self.recordKey) as? Bool ?? true
        let saved = MeetingReminderSchedule.normalize(defaults.array(forKey: Self.minutesKey) as? [Int] ?? MeetingReminderSchedule.defaultMinutes)
        minutes = saved
        schedule = MeetingReminderSchedule(minutes: saved)
        let wrapUpSaved = defaults.object(forKey: Self.wrapUpKey) as? Int ?? WrapUpSchedule.defaultMinutes
        wrapUpMinutes = wrapUpSaved
        wrapUp = WrapUpSchedule(minutes: wrapUpSaved)
    }

    var calendarAllowed: Bool { CalendarTitles.isAllowed }

    func start() {
        restart()
        changesTask = Task { [weak self] in
            for await _ in CalendarTitles.changes {
                self?.refreshedAt = .distantPast
                self?.tick()
            }
        }
    }

    func requestCalendarAccess() async -> Bool {
        let allowed = await CalendarTitles.requestAccess()
        refreshedAt = .distantPast
        tick()
        return allowed
    }

    // MARK: - Actions

    /// Opens the meeting link, and records the call once it starts.
    func join() {
        guard let meeting = current?.meeting else { return }
        dismiss()
        if let link = meeting.link { NSWorkspace.shared.open(link) }
        if recordsWhenJoining { calls.recordNextCall(as: meeting) }
    }

    /// For meetings without a link (in person, a phone call): starts recording right away.
    func recordNow() {
        guard let meeting = current?.meeting else { return }
        dismiss()
        guard !model.isRecording else { return }
        model.startRecording(title: meeting.title)
    }

    func dismiss() {
        current = nil
    }

    /// Clicking the nudge opens the full card, with Join.
    func expandNudge() {
        guard let meeting = nudge else { return }
        nudgeTask?.cancel()
        nudge = nil
        current = MeetingReminder(meeting: meeting, minutesBefore: max(0, Int(meeting.start.timeIntervalSinceNow / 60)))
    }

    private func show(nudge meeting: CalendarMeeting) {
        nudge = meeting
        upNext = meeting
        // No sound: you're in a call, and a chime would go out through your microphone.
        nudgeTask?.cancel()
        nudgeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.nudgeDuration)
            guard !Task.isCancelled else { return }
            self?.nudge = nil
        }
    }

    func addReminder(minutesBefore value: Int) {
        minutes = MeetingReminderSchedule.normalize(minutes + [value])
    }

    func removeReminder(minutesBefore value: Int) {
        minutes = minutes.filter { $0 != value }
    }

    // MARK: - Timing

    private func restart() {
        timer?.invalidate()
        timer = nil
        guard isEnabled || wrapUpMinutes > 0 else { current = nil; return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func tick(now: Date = Date()) {
        guard calendarAllowed, model.settings.completedOnboarding else { return }
        if now.timeIntervalSince(refreshedAt) >= Self.refreshInterval {
            meetings = CalendarTitles.upcomingMeetings(from: now)
            schedule.keep(only: meetings)
            wrapUp.keep(only: meetings)
            refreshedAt = now
        }
        next = meetings.first { $0.start > now }
        if let shown = current, now > shown.meeting.start.addingTimeInterval(Self.cardLifetime)
            || !meetings.contains(where: { $0.id == shown.meeting.id }) {
            current = nil
        }
        if let soon = upNext, now >= soon.start || !model.isRecording {
            upNext = nil
        }
        let inCall = model.isRecording
        if inCall, let meeting = wrapUp.due(in: meetings, current: calls.currentMeetingID, at: now) {
            show(nudge: meeting)
        }
        guard isEnabled, let reminder = schedule.due(in: meetings, at: now) else { return }
        // Don't interrupt the call you're recording with a reminder for the same meeting.
        if inCall, calls.isRecording(reminder.meeting) { return }
        if inCall {
            // Mid-call, another meeting's reminder is a quiet one-line nudge, not a card.
            if nudge?.id != reminder.meeting.id { show(nudge: reminder.meeting) }
            return
        }
        current = reminder
        HUDSounds.play(.reminder)
    }
}
