import EventKit
import Foundation
import TranskribeCore

/// Names a recording after the calendar event happening now ("Weekly sync with Hakan").
@MainActor
enum CalendarTitles {
    private static let store = EKEventStore()

    static var isAllowed: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The event that is on now (or starts within five minutes), preferring ones with other people.
    static func currentEvent(at date: Date = Date()) -> (title: String, attendees: [String])? {
        guard isAllowed else { return nil }
        let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-3 * 3600), end: date.addingTimeInterval(300), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate <= date.addingTimeInterval(300) && $0.endDate >= date }
            .sorted { ($0.attendees?.count ?? 0) > ($1.attendees?.count ?? 0) }
        guard let event = events.first, let title = event.title, !title.isEmpty else { return nil }
        let attendees = (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(\.name)
        return (title, attendees)
    }

    /// Timed meetings that haven't ended and start within `window`, from every calendar on this Mac
    /// (Google, iCloud and Exchange accounts added in System Settings › Internet Accounts).
    static func upcomingMeetings(from date: Date = Date(), within window: TimeInterval = 26 * 3600) -> [CalendarMeeting] {
        guard isAllowed else { return [] }
        let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-3600), end: date.addingTimeInterval(window), calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, event.endDate > date, event.status != .canceled,
                  !declined(event), let title = event.title, !title.isEmpty else { return nil }
            let id = (event.calendarItemIdentifier) + "@" + String(Int(event.startDate.timeIntervalSince1970))
            let link = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
            return CalendarMeeting(id: id, title: title, start: event.startDate, end: event.endDate, link: link)
        }
        .sorted { $0.start < $1.start }
    }

    /// Posted when any calendar on this Mac changes (an event added, moved, or synced in).
    static var changes: NotificationCenter.Notifications {
        NotificationCenter.default.notifications(named: .EKEventStoreChanged, object: store)
    }

    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }
}
