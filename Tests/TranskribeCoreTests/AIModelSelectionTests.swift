import Foundation
import Testing
@testable import TranskribeCore

@Suite struct AIModelSelectionTests {
    @Test func automaticFallbackNeverSelectsXAI() {
        let models = [XAIProvider.grok, ClaudeCodeProvider.sonnet, AppleIntelligenceProvider.model, AnthropicAPIProvider.haiku]
        #expect(AIModelSelection.automaticFallback(models: models, availability: [.xai: .available]) == nil)
        #expect(AIModelSelection.automaticFallback(models: models, availability: [
            .xai: .available, .appleIntelligence: .available, .anthropicAPI: .available,
        ]) == AppleIntelligenceProvider.model)
        #expect(AIModelSelection.automaticFallback(models: models, availability: [
            .xai: .available, .claudeCode: .available, .appleIntelligence: .available,
        ]) == ClaudeCodeProvider.sonnet)
        #expect(AIModelSelection.automaticFallback(models: models, availability: [:]) == nil)
    }

    @Test func openRouterRequiresExplicitSelectionAndNeverFallsBack() {
        let models = [OpenRouterProvider.grok, OpenRouterProvider.haiku, OpenRouterProvider.luna,
                      AppleIntelligenceProvider.model, ClaudeCodeProvider.sonnet]
        #expect(AIModelSelection.automaticFallback(models: models, availability: [.openRouter: .available]) == nil)
        #expect(AIModelSelection.automaticFallback(models: models, availability: [
            .openRouter: .unavailable(reason: "Add an OpenRouter API key in Settings."),
            .appleIntelligence: .available, .claudeCode: .available,
        ], selectedModel: OpenRouterProvider.haiku) == nil)
        #expect(AIModelSelection.automaticFallback(models: models, availability: [
            .openRouter: .available, .appleIntelligence: .available,
        ]) == AppleIntelligenceProvider.model)
    }

    @Test func decodesExistingModelSelections() throws {
        let data = Data(#"{"provider":"claudeCode","id":"sonnet","displayName":"Claude Sonnet (Claude Code)"}"#.utf8)
        let model = try JSONDecoder().decode(AIModel.self, from: data)
        #expect(model.provider == .claudeCode)
        #expect(model.id == "sonnet")
        #expect(try JSONDecoder().decode(AIModel.self, from: JSONEncoder().encode(XAIProvider.grok)) == XAIProvider.grok)
    }
}
