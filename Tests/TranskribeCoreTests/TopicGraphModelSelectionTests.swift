import Testing
@testable import TranskribeCore

@Suite struct TopicGraphModelSelectionTests {
    @Test(arguments: [nil, "", " \n\t"] as [String?])
    func refusesMissingKeys(_ key: String?) {
        #expect(TopicGraphModelSelection.resolve(settings: .default, openRouterKey: key) == nil)
    }

    @Test func selectsExactlyTheSavedCuratedModels() throws {
        for decision in DecisionModel.curated {
            for naming in OpenRouterProvider().models {
                let settings = TopicGraphSettings(decisionModelID: decision.id, namingModelID: naming.id)
                let selection = try #require(TopicGraphModelSelection.resolve(settings: settings, openRouterKey: "test-key"))
                #expect(selection.decisionModel == decision)
                #expect(selection.namingModel == naming)
            }
        }
    }

    @Test(arguments: [
        TopicGraphSettings(decisionModelID: "retired-decision"),
        TopicGraphSettings(namingModelID: "retired-naming"),
        TopicGraphSettings(decisionModelID: "", namingModelID: ""),
        TopicGraphSettings(decisionModelID: OpenRouterProvider.luna.id),
        TopicGraphSettings(namingModelID: DecisionModel.jev.id),
    ])
    func refusesUnavailableSavedModelsWithoutChangingThem(_ settings: TopicGraphSettings) {
        let defaults = Fixtures.temporaryDefaults()
        CopilotSettings(topicGraph: true, topicGraphSettings: settings).save(to: defaults)
        let loaded = CopilotSettings.load(from: defaults)
        #expect(loaded.topicGraphSettings == settings)
        #expect(TopicGraphModelSelection.resolve(settings: loaded.topicGraphSettings, openRouterKey: "test-key") == nil)
    }
}
