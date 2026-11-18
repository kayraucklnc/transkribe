import Foundation

/// What to do with a call recording when the call's app lets go of the microphone.
///
/// Muted people are still in the meeting, and a mic can go quiet for reasons that aren't
/// hanging up (switching headsets, a browser hiccup). So while the meeting is still on the
/// calendar, a quiet mic alone never stops the recording: it keeps going until the planned end,
/// unless there's proof you left (the meeting tab is gone). After the planned end, the call's
/// real end stops it, however late the meeting ran.
public enum CallEndPolicy {
    public enum Decision: Equatable, Sendable {
        case stop
        /// Keep recording; stop at this time if the call hasn't come back by then.
        case keepUntil(Date)
    }

    /// - Parameters:
    ///   - scheduledEnd: The calendar end of the meeting being recorded, if it's from the calendar.
    ///   - leftMeeting: Whether the browser shows the meeting tab is gone (false when unknown).
    public static func decide(now: Date, scheduledEnd: Date?, leftMeeting: Bool) -> Decision {
        if leftMeeting { return .stop }
        if let scheduledEnd, now < scheduledEnd { return .keepUntil(scheduledEnd) }
        return .stop
    }

    /// While a recording waits for the planned end (`keepUntil`), whether to stop now: the
    /// planned end came, or the meeting tab is gone (you hung up, then closed it).
    /// - Parameter meetingOpen: Whether the browser still has the meeting tab (nil when unknown).
    public static func stopsWhileWaiting(now: Date, until end: Date, meetingOpen: Bool?) -> Bool {
        meetingOpen == false || now >= end
    }

    /// How long before a call picks up the mic a recording you started yourself still counts as
    /// that call's: pressing Record, then joining through a lobby.
    public static let joinLead: TimeInterval = 2 * 60

    /// Whether a recording you started yourself is for the call, so the call's end stops it too.
    /// One started during the call, or just before joining, is; a longer one a call interrupts
    /// (an in-person meeting) isn't.
    public static func belongsToCall(recordingStartedAt start: Date, callStartedAt callStart: Date) -> Bool {
        start >= callStart - joinLead
    }
}
