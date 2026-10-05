import EventKit
import Foundation

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
}
