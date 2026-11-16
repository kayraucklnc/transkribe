import Foundation

public struct TopicGraphModelSelection: Equatable, Sendable {
    public let decisionModel: DecisionModel
    public let namingModel: AIModel

    public static func resolve(settings: TopicGraphSettings, openRouterKey: String?) -> TopicGraphModelSelection? {
        guard let key = openRouterKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
              let decision = DecisionModel.curated.first(where: { $0.id == settings.decisionModelID }),
              let naming = OpenRouterProvider().models.first(where: { $0.id == settings.namingModelID }) else { return nil }
        return TopicGraphModelSelection(decisionModel: decision, namingModel: naming)
    }
}
