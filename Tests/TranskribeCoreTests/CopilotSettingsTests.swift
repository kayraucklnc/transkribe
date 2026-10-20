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
}
