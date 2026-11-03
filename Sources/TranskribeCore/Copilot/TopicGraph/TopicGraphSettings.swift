import Foundation

public struct TopicGraphSettings: Codable, Equatable, Sendable {
    public var decisionModelID: String
    public var namingModelID: String
    public var namingRefreshWords: Int

    public static let `default` = TopicGraphSettings()

    private enum CodingKeys: String, CodingKey {
        case decisionModelID
        case namingModelID
        case namingRefreshWords
    }

    public init(decisionModelID: String = DecisionModel.jev.id,
                namingModelID: String = OpenRouterProvider.luna.id, namingRefreshWords: Int = 60) {
        self.decisionModelID = decisionModelID
        self.namingModelID = namingModelID
        self.namingRefreshWords = namingRefreshWords
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        decisionModelID = try values.decodeIfPresent(String.self, forKey: .decisionModelID) ?? DecisionModel.jev.id
        namingModelID = try values.decodeIfPresent(String.self, forKey: .namingModelID) ?? OpenRouterProvider.luna.id
        namingRefreshWords = try values.decodeIfPresent(Int.self, forKey: .namingRefreshWords) ?? 60
    }
}
