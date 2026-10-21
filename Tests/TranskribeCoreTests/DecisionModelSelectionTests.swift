import Testing
@testable import TranskribeCore

@Suite struct DecisionModelSelectionTests {
    @Test func unavailableAppleNeverUsesPresentAnthropicKey() async {
        let cloud = AnthropicAPIProvider(apiKey: { "test-anthropic-key" })
        let availability: [AIProviderKind: AIAvailability] = [
            .appleIntelligence: .unavailable(reason: "Apple Intelligence is disabled."),
            .anthropicAPI: await cloud.availability(),
        ]
        #expect(availability[.anthropicAPI] == .available)
        let provider = DecisionModelSelection.provider(for: AppleIntelligenceProvider.model,
            providers: [AppleIntelligenceProvider(), cloud], availability: availability)
        #expect(provider == nil)
    }

    @Test func modelNoLongerOfferedNeverUsesAnotherModel() {
        let removed = AIModel(provider: .anthropicAPI, id: "removed-model", displayName: "Removed model")
        let provider = DecisionModelSelection.provider(for: removed,
            providers: [AnthropicAPIProvider(apiKey: { "test-anthropic-key" })],
            availability: [.anthropicAPI: .available])
        #expect(provider == nil)
    }

    @Test(arguments: [AppleIntelligenceProvider.model, ClaudeCodeProvider.haiku,
                      AnthropicAPIProvider.haiku, XAIProvider.grok])
    func availableChoiceUsesOnlyItsOwnProvider(_ model: AIModel) {
        let providers: [any AIProvider] = [ClaudeCodeProvider(), AppleIntelligenceProvider(),
                                           AnthropicAPIProvider(), XAIProvider()]
        let availability = Dictionary(uniqueKeysWithValues: AIProviderKind.allCases.map { ($0, AIAvailability.available) })
        let provider = DecisionModelSelection.provider(for: model, providers: providers, availability: availability)
        #expect(provider?.kind == model.provider)
    }

    @Test func uncheckedOrMissingProviderStopsBackgroundWork() {
        let cloud = AnthropicAPIProvider(apiKey: { "test-anthropic-key" })
        #expect(DecisionModelSelection.provider(for: AppleIntelligenceProvider.model,
            providers: [AppleIntelligenceProvider(), cloud], availability: [.anthropicAPI: .available]) == nil)
        #expect(DecisionModelSelection.provider(for: AppleIntelligenceProvider.model,
            providers: [cloud], availability: [.appleIntelligence: .available, .anthropicAPI: .available]) == nil)
    }
}
