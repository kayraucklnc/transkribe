import Foundation

/// A meeting from the calendar, reduced to what reminders and joining need.
public struct CalendarMeeting: Equatable, Sendable, Identifiable {
    /// Stable for one occurrence: repeating events share an event id, so the start is part of it.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let link: URL?

    public init(id: String, title: String, start: Date, end: Date, link: URL?) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.link = link
    }
}

/// A reminder that is due now: `minutesBefore` is the reminder time that triggered it (0 is "at start").
public struct MeetingReminder: Equatable, Sendable {
    public let meeting: CalendarMeeting
    public let minutesBefore: Int

    public init(meeting: CalendarMeeting, minutesBefore: Int) {
        self.meeting = meeting
        self.minutesBefore = minutesBefore
    }
}

/// Decides when to remind about meetings, given reminder times in minutes before the start.
/// Each reminder time fires once per meeting. If several have already passed (the Mac was
/// asleep, the app just launched), only the latest one fires.
public struct MeetingReminderSchedule: Sendable {
    /// How long after a meeting starts a reminder is still worth showing.
    public static let lateWindow: TimeInterval = 2 * 60
    public static let maximumMinutes = 24 * 60
    public static let defaultMinutes = [10, 5]

    public private(set) var minutes: [Int]
    /// Reminder times already shown, by meeting id.
    private var fired: [String: Set<Int>] = [:]

    public init(minutes: [Int]) {
        self.minutes = Self.normalize(minutes)
    }

    /// Unique, within 0…one day, latest last (10, 5, 1, 0).
    public static func normalize(_ minutes: [Int]) -> [Int] {
        Array(Set(minutes.filter { (0...maximumMinutes).contains($0) })).sorted(by: >)
    }

    public mutating func setMinutes(_ minutes: [Int]) {
        self.minutes = Self.normalize(minutes)
    }

    /// The reminder to show now, if any. Marks it (and any earlier ones it replaces) as shown.
    public mutating func due(in meetings: [CalendarMeeting], at now: Date) -> MeetingReminder? {
        for meeting in meetings.sorted(by: { $0.start < $1.start }) {
            guard now < meeting.start.addingTimeInterval(Self.lateWindow) else { continue }
            let passed = minutes.filter { now >= meeting.start.addingTimeInterval(-Double($0) * 60) }
            guard let latest = passed.min() else { continue }
            guard fired[meeting.id]?.contains(latest) != true else { continue }
            fired[meeting.id, default: []].formUnion(passed)
            return MeetingReminder(meeting: meeting, minutesBefore: latest)
        }
        return nil
    }

    /// Keeps only the meetings still on the calendar, so the record stays small over days of uptime.
    public mutating func keep(only meetings: [CalendarMeeting]) {
        let ids = Set(meetings.map(\.id))
        fired = fired.filter { ids.contains($0.key) }
    }
}

/// Short, human countdowns for a meeting: "in 5 min", "starting now", "started 2 min ago".
public enum MeetingCountdown {
    public static func text(until start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds > 59 {
            let minutes = Int((seconds / 60).rounded(.up))
            if minutes >= 60 {
                let hours = minutes / 60, rest = minutes % 60
                return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
            }
            return "in \(minutes) min"
        }
        if seconds > -60 { return "starting now" }
        return "started \(Int(-seconds / 60)) min ago"
    }

    /// How a reminder time reads in Settings: "At start", "5 min before", "1 h before".
    public static func label(minutesBefore minutes: Int) -> String {
        if minutes == 0 { return "At start" }
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60) h before" }
        return "\(minutes) min before"
    }
}
