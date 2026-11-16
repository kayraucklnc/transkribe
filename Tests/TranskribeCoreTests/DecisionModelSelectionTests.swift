import Foundation
import Testing
@testable import TranskribeCore

@Suite struct DecisionModelSelectionTests {
    @Test func choicesContainOnlyHaikuAndCuratedDecisions() throws {
        #expect(DecisionModelSelection.choices == [.haiku, .openRouter(.jev), .openRouter(.luna)])
        for choice in DecisionModelSelection.choices {
            #expect(try JSONDecoder().decode(DecisionModelSelection.self,
                from: JSONEncoder().encode(choice)) == choice)
        }
    }

    @Test func unavailableHaikuNeverUsesAnotherProvider() {
        let providers: [any AIProvider] = [AnthropicAPIProvider(), ClaudeCodeProvider(), OpenRouterProvider()]
        #expect(DecisionModelSelection.provider(for: .haiku, providers: providers,
            availability: [.anthropicAPI: .unavailable(reason: "No key"), .claudeCode: .available,
                           .openRouter: .available]) == nil)
    }

    @Test func haikuUsesOnlyAnthropicAndDecisionsNeverUseChatProviders() throws {
        let providers: [any AIProvider] = [AnthropicAPIProvider(), OpenRouterProvider()]
        #expect(DecisionModelSelection.provider(for: .haiku, providers: providers,
            availability: [.anthropicAPI: .available])?.kind == .anthropicAPI)
        #expect(DecisionModelSelection.provider(for: .openRouter(.jev), providers: providers,
            availability: [.anthropicAPI: .available, .openRouter: .available]) == nil)
        let removed = DecisionModelSelection.openRouter(DecisionModel(id: "removed", displayName: "Removed"))
        #expect(!removed.isSupported)
        #expect(try JSONDecoder().decode(DecisionModelSelection.self,
            from: JSONEncoder().encode(removed)) == removed)
    }
}
