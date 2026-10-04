import Foundation
import Testing
@testable import TranskribeCore

@Suite struct CallWatchTests {
    private let zoom = "us.zoom.xos"

    @Test func knowsCommonCallApps() {
        #expect(CallApps.name(for: "us.zoom.xos") == "Zoom")
        #expect(CallApps.name(for: "com.apple.FaceTime") == "FaceTime")
        #expect(CallApps.name(for: "com.google.Chrome") == "Chrome")
        #expect(CallApps.name(for: "com.apple.VoiceMemos") == nil)
    }

    @Test func aCallStartsAfterTheMicIsHeldForAFewSeconds() {
        var watch = CallWatch()
        let start = Date()
        #expect(watch.update(micApps: [zoom], at: start) == nil)
        #expect(watch.update(micApps: [zoom], at: start + 1) == nil)
        #expect(watch.update(micApps: [zoom], at: start + 4) == .started(app: "Zoom"))
        #expect(watch.update(micApps: [zoom], at: start + 6) == nil) // reported once
    }

    @Test func briefMicUseIsNotACall() {
        var watch = CallWatch()
        let start = Date()
        _ = watch.update(micApps: [zoom], at: start)
        #expect(watch.update(micApps: [], at: start + 1) == nil)
        #expect(watch.update(micApps: [zoom], at: start + 2) == nil) // the clock starts over
    }

    @Test func aCallEndsAfterTheMicStaysFreeForAWhile() {
        var watch = CallWatch()
        let start = Date()
        _ = watch.update(micApps: [zoom], at: start)
        _ = watch.update(micApps: [zoom], at: start + 4)
        #expect(watch.update(micApps: [], at: start + 10) == nil) // could be a mute or a hiccup
        #expect(watch.update(micApps: [zoom], at: start + 12) == nil)
        #expect(watch.update(micApps: [], at: start + 20) == nil)
        #expect(watch.update(micApps: [], at: start + 30) == nil)
        #expect(watch.update(micApps: [], at: start + 36) == .ended(app: "Zoom"))
    }

    @Test func appsThatAreNotCallsAreIgnored() {
        var watch = CallWatch()
        let start = Date()
        _ = watch.update(micApps: ["com.apple.VoiceMemos"], at: start)
        #expect(watch.update(micApps: ["com.apple.VoiceMemos"], at: start + 10) == nil)
    }
}
