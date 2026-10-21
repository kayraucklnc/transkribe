import Foundation
import Testing
@testable import TranskribeCore

@Suite struct CopilotSettingsTests {
    @Test func intentsDefaultOffAndEnableLiveInsights() throws {
        let old = try JSONDecoder().decode(CopilotSettings.self, from: Data("{}".utf8))
        #expect(!old.intents)
        let settings = CopilotSettings(intents: true)
        #expect(settings.showsInsights(isLive: true))
        #expect(!settings.canAsk(status: .transcribing, isLive: true))
        let defaults = Fixtures.temporaryDefaults()
        settings.save(to: defaults)
        #expect(CopilotSettings.load(from: defaults) == settings)
    }

    @Test func decisionModelDefaultsToHaikuAndPersistsIndependently() throws {
        let old = try JSONDecoder().decode(CopilotSettings.self,
            from: Data(#"{"fastLiveWindow":true}"#.utf8))
        #expect(old.decisionModel == AnthropicAPIProvider.haiku)
        #expect(old.fastLiveWindow)
        let null = try JSONDecoder().decode(CopilotSettings.self,
            from: Data(#"{"decisionModel":null}"#.utf8))
        #expect(null.decisionModel == AnthropicAPIProvider.haiku)

        let defaults = Fixtures.temporaryDefaults()
        var settings = old
        settings.decisionModel = AppleIntelligenceProvider.model
        settings.save(to: defaults)
        #expect(CopilotSettings.load(from: defaults).decisionModel == AppleIntelligenceProvider.model)
        #expect(CopilotSettings.load(from: defaults).fastLiveWindow)
        #expect(!CopilotSettings.load(from: defaults).askWhileLive)
    }

    @Test(arguments: ["{}", #"{"retiredFlag":true}"#, #"{"fastLiveWindow":null,"futureFlag":true}"#])
    func missingFlagsDecodeToDefaults(_ json: String) throws {
        let settings = try JSONDecoder().decode(CopilotSettings.self, from: Data(json.utf8))
        #expect(settings == .default)
        #expect(!settings.fastLiveWindow)
    }

    @Test func mcpShowsLiveAskWithoutEnablingTypedQuestions() {
        let settings = CopilotSettings(mcpServer: true)
        #expect(settings.showsInsights(isLive: true))
        #expect(!settings.canAsk(status: .transcribing, isLive: true))
        #expect(!CopilotSettings.default.showsInsights(isLive: true))
        #expect(CopilotSettings.default.showsInsights(isLive: false))
    }

    @Test func webhookDefaultsOffAndPersistsOnlyTheURL() throws {
        let old = try JSONDecoder().decode(CopilotSettings.self, from: Data(#"{"fastLiveWindow":true}"#.utf8))
        #expect(old.webhook == nil)
        #expect(old.fastLiveWindow)
        let null = try JSONDecoder().decode(CopilotSettings.self, from: Data(#"{"webhook":null}"#.utf8))
        #expect(null == .default)
        let defaults = Fixtures.temporaryDefaults()
        let settings = CopilotSettings(webhook: URL(string: "https://webhook.example/events"))
        settings.save(to: defaults)
        #expect(CopilotSettings.load(from: defaults) == settings)
        let data = try #require(defaults.data(forKey: "copilotSettings"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["webhook"] as? String == "https://webhook.example/events")
        #expect(Set(json.keys) == ["fastLiveWindow", "askWhileLive", "mcpServer", "mcpPort", "mcpReadScopeDays", "webhook", "decisionModel", "intents"])
    }

    @Test func mcpSettingsPersistWithoutSecretsAndDecodeOldData() throws {
        let old = try JSONDecoder().decode(CopilotSettings.self, from: Data("{}".utf8))
        #expect(!old.mcpServer)
        #expect(old.mcpPort == 7788)
        #expect(old.mcpReadScopeDays == 7)
        let settings = CopilotSettings(mcpServer: true, mcpPort: 8899, mcpReadScopeDays: 3)
        let data = try JSONEncoder().encode(settings)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["fastLiveWindow", "askWhileLive", "mcpServer", "mcpPort", "mcpReadScopeDays", "decisionModel", "intents"])
        #expect(!String(decoding: data, as: UTF8.self).lowercased().contains("token"))
        #expect(try JSONDecoder().decode(CopilotSettings.self, from: data) == settings)
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
