import Foundation
import Testing
@testable import TranskribeCore

@Suite struct CopilotSettingsTests {
    @Test(arguments: ["{}", #"{"retiredFlag":true}"#, #"{"fastLiveWindow":null,"futureFlag":true}"#])
    func missingFlagsDecodeToDefaults(_ json: String) throws {
        let settings = try JSONDecoder().decode(CopilotSettings.self, from: Data(json.utf8))
        #expect(settings == .default)
        #expect(!settings.fastLiveWindow)
    }

    @Test func liveAskFlagDefaultsAndPersistsIndependently() throws {
        let old = try JSONDecoder().decode(CopilotSettings.self,
            from: Data(#"{"fastLiveWindow":true}"#.utf8))
        #expect(!old.askWhileLive)
        let defaults = Fixtures.temporaryDefaults()
        let enabled = CopilotSettings(askWhileLive: true)
        enabled.save(to: defaults)
        #expect(CopilotSettings.load(from: defaults) == enabled)
        #expect(!enabled.fastLiveWindow)
        let null = try JSONDecoder().decode(CopilotSettings.self,
            from: Data(#"{"askWhileLive":null}"#.utf8))
        #expect(null == .default)
    }

    @Test func canAskRespectsStatusAndLiveOptIn() {
        let cases: [(TranscriptStatus, Bool, Bool, Bool)] = [
            (.pending, false, false, false),
            (.pending, false, true, false),
            (.pending, true, false, false),
            (.pending, true, true, false),
            (.transcribing, false, false, false),
            (.transcribing, false, true, false),
            (.transcribing, true, false, false),
            (.transcribing, true, true, true),
            (.done, false, false, true),
            (.done, false, true, true),
            (.done, true, false, false),
            (.done, true, true, true),
            (.failed("Transcription failed."), false, false, false),
            (.failed("Transcription failed."), false, true, false),
            (.failed("Transcription failed."), true, false, false),
            (.failed("Transcription failed."), true, true, false),
        ]
        for (status, isLive, enabled, expected) in cases {
            #expect(CopilotSettings(askWhileLive: enabled).canAsk(status: status, isLive: isLive) == expected,
                    "status: \(status), live: \(isLive), flag: \(enabled)")
        }
    }

    @Test(arguments: ["", "not JSON", "{}", #"{"retiredFlag":true}"#, #"{"fastLiveWindow":"yes"}"#])
    func absentOrInvalidSavedFlagsUseDefaults(_ json: String) {
        let defaults = Fixtures.temporaryDefaults()
        #expect(CopilotSettings.load(from: defaults) == .default)
        defaults.set(Data(json.utf8), forKey: "copilotSettings")
        #expect(CopilotSettings.load(from: defaults) == .default)
    }

    @Test func enabledFlagPersistsWithoutChangingTranscriptionSettings() throws {
        let defaults = Fixtures.temporaryDefaults()
        var transcription = TranscriptionSettings.default
        transcription.languages = ["it"]
        transcription.quality = .best
        transcription.save(to: defaults)

        let settings = try JSONDecoder().decode(CopilotSettings.self,
            from: Data(#"{"fastLiveWindow":true,"futureFlag":true}"#.utf8))
        #expect(settings.fastLiveWindow)
        settings.save(to: defaults)

        #expect(CopilotSettings.load(from: defaults) == settings)
        #expect(TranscriptionSettings.load(from: defaults) == transcription)
        let data = try #require(defaults.data(forKey: "copilotSettings"))
        #expect(try JSONDecoder().decode(CopilotSettings.self, from: data).fastLiveWindow)
    }

    @Test func livePlannerChangesOnlyWhenEnabled() {
        let standard = CopilotSettings.default.windowPlanner(isLive: true)
        #expect(standard.minimumWindow == 30)
        #expect(standard.maximumWindow == 120)
        #expect(standard.tailGuard == 5)

        let fast = CopilotSettings(fastLiveWindow: true).windowPlanner(isLive: true)
        #expect(fast.minimumWindow == 10)
        #expect(fast.maximumWindow == 60)
        #expect(fast.tailGuard == 3)
    }

    @Test(arguments: [false, true])
    func filePlannerDoesNotChange(_ fastLiveWindow: Bool) {
        let planner = CopilotSettings(fastLiveWindow: fastLiveWindow).windowPlanner(isLive: false)
        #expect(planner.minimumWindow == 30)
        #expect(planner.maximumWindow == 600)
        #expect(planner.tailGuard == 5)
    }
}
