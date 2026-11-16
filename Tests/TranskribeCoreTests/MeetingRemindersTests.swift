import Foundation
import Testing
@testable import TranskribeCore

@Suite struct MeetingLinkTests {
    @Test func findsGoogleMeetInGoogleCalendarNotes() {
        let notes = """
        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        Join with Google Meet: https://meet.google.com/abc-defg-hij
        Or dial: (US) +1 555-555-0100 PIN: 123456#
        Learn more about Meet at: https://support.google.com/a/users/answer/9282720
        """
        #expect(MeetingLink.find(in: [nil, "Room 4", notes])?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func findsZoomAndTeamsLinksAndTrimsPunctuation() {
        #expect(MeetingLink.find(in: ["Zoom (https://acme.zoom.us/j/123456789?pwd=xyz)."])?.absoluteString
            == "https://acme.zoom.us/j/123456789?pwd=xyz")
        let teams = "<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0>"
        #expect(MeetingLink.find(in: [teams])?.host == "teams.microsoft.com")
    }

    @Test func prefersTheEarlierFieldAndIgnoresOtherLinks() {
        let url = MeetingLink.find(in: ["https://docs.google.com/document/d/1", "https://meet.google.com/aaa-bbbb-ccc",
                                        "https://zoom.us/j/1"])
        #expect(url?.host == "meet.google.com")
        #expect(MeetingLink.find(in: ["Agenda: https://zoom.us/pricing and https://meet.google.com/"]) == nil)
        #expect(MeetingLink.find(in: []) == nil)
    }
}

@Suite struct MeetingReminderScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var meeting: CalendarMeeting {
        CalendarMeeting(id: "sync", title: "Weekly sync", start: start, end: start + 1800, link: nil)
    }

    @Test func normalizesReminderTimes() {
        #expect(MeetingReminderSchedule.normalize([5, 10, 5, -1, 0, 2000]) == [10, 5, 0])
    }

    @Test func firesEachReminderTimeOnce() {
        var schedule = MeetingReminderSchedule(minutes: [10, 5])
        #expect(schedule.due(in: [meeting], at: start - 11 * 60) == nil)
        #expect(schedule.due(in: [meeting], at: start - 10 * 60)?.minutesBefore == 10)
        #expect(schedule.due(in: [meeting], at: start - 9 * 60) == nil)
        #expect(schedule.due(in: [meeting], at: start - 5 * 60)?.minutesBefore == 5)
        #expect(schedule.due(in: [meeting], at: start - 4 * 60) == nil)
        #expect(schedule.due(in: [meeting], at: start) == nil)
    }

    @Test func onlyTheLatestOfSeveralMissedRemindersFires() {
        var schedule = MeetingReminderSchedule(minutes: [15, 10, 5])
        // The Mac woke up three minutes before the meeting.
        #expect(schedule.due(in: [meeting], at: start - 3 * 60)?.minutesBefore == 5)
        #expect(schedule.due(in: [meeting], at: start - 2 * 60) == nil)
    }

    @Test func atStartReminderAndLateness() {
        var schedule = MeetingReminderSchedule(minutes: [0])
        #expect(schedule.due(in: [meeting], at: start - 30) == nil)
        #expect(schedule.due(in: [meeting], at: start + 10)?.minutesBefore == 0)

        var late = MeetingReminderSchedule(minutes: [5])
        #expect(late.due(in: [meeting], at: start + MeetingReminderSchedule.lateWindow + 1) == nil)
    }

    @Test func remindsAboutTheSoonestMeetingFirst() {
        let later = CalendarMeeting(id: "later", title: "1:1", start: start + 120, end: start + 900, link: nil)
        var schedule = MeetingReminderSchedule(minutes: [5])
        #expect(schedule.due(in: [later, meeting], at: start - 60)?.meeting.id == "sync")
        #expect(schedule.due(in: [later, meeting], at: start - 60)?.meeting.id == "later")
    }

    @Test func changingTimesKeepsWhatWasShown() {
        var schedule = MeetingReminderSchedule(minutes: [10])
        _ = schedule.due(in: [meeting], at: start - 10 * 60)
        schedule.setMinutes([10, 2])
        #expect(schedule.due(in: [meeting], at: start - 8 * 60) == nil)
        #expect(schedule.due(in: [meeting], at: start - 2 * 60)?.minutesBefore == 2)
        schedule.keep(only: [])
        #expect(schedule.due(in: [meeting], at: start - 60)?.minutesBefore == 2) // forgotten, so it shows again
    }

    @Test func countdownText() {
        #expect(MeetingCountdown.text(until: start, now: start - 300) == "in 5 min")
        #expect(MeetingCountdown.text(until: start, now: start - 290) == "in 5 min")
        #expect(MeetingCountdown.text(until: start, now: start - 30) == "starting now")
        #expect(MeetingCountdown.text(until: start, now: start + 130) == "started 2 min ago")
        #expect(MeetingCountdown.text(until: start, now: start - 5400) == "in 1 h 30 min")
        #expect(MeetingCountdown.label(minutesBefore: 0) == "At start")
        #expect(MeetingCountdown.label(minutesBefore: 60) == "1 h before")
        #expect(MeetingCountdown.label(minutesBefore: 5) == "5 min before")
    }
}

@Suite struct ChimeTests {
    @Test func startRisesAndStopFalls() {
        #expect(Chime.start.notes.first! < Chime.start.notes.last!)
        #expect(Chime.stop.notes.first! > Chime.stop.notes.last!)
    }

    @Test func chimesAreShortQuietAndValidWAV() {
        for chime in Chime.allCases {
            let samples = chime.samples()
            #expect(Double(samples.count) / 44_100 < 0.8)
            #expect(samples.map(abs).max()! < 0.3)
            let wav = chime.wav()
            #expect(wav.prefix(4) == Data("RIFF".utf8))
            #expect(wav.count == 44 + samples.count * 2)
        }
    }
}

@Suite struct CallAppHelperTests {
    @Test func browserHelperProcessesCountAsTheBrowser() {
        #expect(CallApps.name(for: "com.google.Chrome.helper") == "Chrome")
        #expect(CallApps.name(for: "com.google.Chrome.helper.renderer") == "Chrome")
        #expect(CallApps.name(for: "com.microsoft.edgemac.helper") == "Edge")
        #expect(CallApps.name(for: "com.google") == nil)
        #expect(CallApps.name(for: "com.google.Drive") == nil)
    }
}
