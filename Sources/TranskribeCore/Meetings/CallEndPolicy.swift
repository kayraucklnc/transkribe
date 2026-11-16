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
}
