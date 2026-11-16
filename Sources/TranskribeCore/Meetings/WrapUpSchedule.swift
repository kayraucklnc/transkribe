import Foundation

/// Decides when to nudge "wrap up, your next meeting is soon" while you're in a call: once per
/// upcoming meeting, when it starts within `minutes`. The meeting you're in never counts as next.
public struct WrapUpSchedule: Sendable {
    public static let defaultMinutes = 5
    public static let choices = [0, 2, 3, 5, 10]

    /// How long before the next meeting to nudge; 0 turns it off.
    public var minutes: Int
    private var nudged: Set<CalendarMeeting.ID> = []

    public init(minutes: Int = Self.defaultMinutes) {
        self.minutes = minutes
    }

    /// The next meeting to nudge about now, if any. Each meeting is nudged once.
    public mutating func due(in meetings: [CalendarMeeting], current: CalendarMeeting.ID?, at now: Date) -> CalendarMeeting? {
        guard minutes > 0 else { return nil }
        let lead = TimeInterval(minutes * 60)
        guard let next = meetings
            .filter({ $0.start > now && $0.id != current })
            .min(by: { $0.start < $1.start }),
            next.start.timeIntervalSince(now) <= lead,
            !nudged.contains(next.id) else { return nil }
        nudged.insert(next.id)
        return next
    }

    /// Keeps only meetings still on the calendar, so the record stays small over days of uptime.
    public mutating func keep(only meetings: [CalendarMeeting]) {
        nudged.formIntersection(meetings.map(\.id))
    }
}
