import Foundation
import Testing
@testable import TranskribeCore

@Suite struct BrowserMeetingTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func recognizesMeetingPagesButNotHomePages() {
        #expect(BrowserMeeting.from(url: url("https://meet.google.com/abc-defg-hij?authuser=0"))
            == BrowserMeeting(service: .googleMeet, code: "abc-defg-hij"))
        #expect(BrowserMeeting.from(url: url("https://meet.google.com/")) == nil)
        #expect(BrowserMeeting.from(url: url("https://meet.google.com/landing")) == nil)
        #expect(BrowserMeeting.from(url: url("https://app.zoom.us/wc/81234567890/join?fromPWA=1"))
            == BrowserMeeting(service: .zoom, code: "81234567890"))
        #expect(BrowserMeeting.from(url: url("https://zoom.us/pricing")) == nil)
        #expect(BrowserMeeting.from(url: url("https://teams.microsoft.com/v2/"))?.service == .teams)
        #expect(BrowserMeeting.from(url: url("https://docs.google.com/document/d/1")) == nil)
    }

    @Test func readsWindowTitlesFromFirefoxAndZen() {
        #expect(BrowserMeeting.from(windowTitle: "Meet - abc-defg-hij — Mozilla Firefox")
            == BrowserMeeting(service: .googleMeet, code: "abc-defg-hij"))
        #expect(BrowserMeeting.from(windowTitle: "Meet – xyz-abcd-efg")?.code == "xyz-abcd-efg")
        #expect(BrowserMeeting.from(windowTitle: "Zoom Meeting — Zen Browser")?.service == .zoom)
        #expect(BrowserMeeting.from(windowTitle: "Meeting with Ada | Microsoft Teams")?.service == .teams)
        #expect(BrowserMeeting.from(windowTitle: "Inbox (3) - Gmail") == nil)
        #expect(BrowserMeeting.from(windowTitle: "Meeting notes abc-defg-hij.docx") == nil)
    }

    @Test func matchesTheCalendarLinkForTheSameMeeting() {
        let tab = BrowserMeeting(service: .googleMeet, code: "abc-defg-hij")
        #expect(tab.matches(link: url("https://meet.google.com/abc-defg-hij")))
        #expect(!tab.matches(link: url("https://meet.google.com/zzz-zzzz-zzz")))
        #expect(!tab.matches(link: url("https://zoom.us/j/81234567890")))
        #expect(BrowserMeeting(service: .zoom, code: "81234567890").matches(link: url("https://acme.zoom.us/j/81234567890?pwd=x")))
        #expect(!BrowserMeeting(service: .teams, code: nil).matches(link: url("https://teams.microsoft.com/l/meetup-join/x")))
    }
}

@Suite struct BrowsersTests {
    @Test func knowsZenBraveAndHelpers() {
        #expect(Browsers.browser(for: "app.zen-browser.zen")?.reading == .windowTitles)
        #expect(Browsers.browser(for: "com.brave.Browser.helper")?.name == "Brave")
        #expect(Browsers.browser(for: "com.google.Chrome.helper.renderer")?.reading == .chromiumScript)
        #expect(Browsers.browser(for: "com.apple.Safari")?.reading == .safariScript)
        #expect(Browsers.browser(for: "us.zoom.xos") == nil)
        #expect(CallApps.name(for: "app.zen-browser.zen") == "Zen")
        #expect(CallApps.name(for: "com.vivaldi.Vivaldi") == "Vivaldi")
    }

    @Test func onlyScriptableBrowsersNeedAutomation() {
        #expect(Browsers.browser(for: "com.google.Chrome")?.needsAutomation == true)
        #expect(Browsers.browser(for: "org.mozilla.firefox")?.needsAutomation == false)
    }
}

@Suite struct CallWatchMeetingTabTests {
    private let chrome = "com.google.Chrome.helper"

    @Test func remembersWhichProcessHasTheCall() {
        var watch = CallWatch()
        let start = Date()
        _ = watch.update(micApps: [chrome], at: start)
        #expect(watch.update(micApps: [chrome], at: start + 4) == .started(app: "Chrome"))
        #expect(watch.activeBundleID == chrome)
    }

    @Test func anOpenMeetingTabGivesTheMicLongerToComeBack() {
        var watch = CallWatch()
        let start = Date()
        _ = watch.update(micApps: [chrome], at: start)
        _ = watch.update(micApps: [chrome], at: start + 4)
        #expect(watch.update(micApps: [], meetingOpen: true, at: start + 10) == nil)
        #expect(watch.update(micApps: [], meetingOpen: true, at: start + 30) == nil) // 15 s would have ended it
        #expect(watch.update(micApps: [], meetingOpen: true, at: start + 56) == .ended(app: "Chrome"))
        #expect(watch.activeBundleID == nil)
    }

    @Test func aClosedMeetingTabEndsOnTheUsualSchedule() {
        var watch = CallWatch()
        let start = Date()
        _ = watch.update(micApps: [chrome], at: start)
        _ = watch.update(micApps: [chrome], at: start + 4)
        #expect(watch.update(micApps: [], meetingOpen: false, at: start + 10) == nil)
        #expect(watch.update(micApps: [], meetingOpen: false, at: start + 26) == .ended(app: "Chrome"))
    }
}

@Suite struct CallEndPolicyTests {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aQuietMicBeforeThePlannedEndKeepsRecording() {
        #expect(CallEndPolicy.decide(now: end - 1200, scheduledEnd: end, leftMeeting: false) == .keepUntil(end))
    }

    @Test func leavingTheMeetingStopsEvenBeforeThePlannedEnd() {
        #expect(CallEndPolicy.decide(now: end - 1200, scheduledEnd: end, leftMeeting: true) == .stop)
    }

    @Test func afterThePlannedEndTheRealEndStopsIt() {
        #expect(CallEndPolicy.decide(now: end + 900, scheduledEnd: end, leftMeeting: false) == .stop)
    }

    @Test func callsWithoutACalendarMeetingStopWhenTheCallEnds() {
        #expect(CallEndPolicy.decide(now: end, scheduledEnd: nil, leftMeeting: false) == .stop)
    }
}
