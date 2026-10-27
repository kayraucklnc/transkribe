import Foundation

public struct TopicGraphSettings: Codable, Equatable, Sendable {
    public var namingRefreshWords: Int

    public static let `default` = TopicGraphSettings()

    private enum CodingKeys: String, CodingKey {
        case namingRefreshWords
    }

    public init(namingRefreshWords: Int = 60) {
        self.namingRefreshWords = namingRefreshWords
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        namingRefreshWords = try values.decodeIfPresent(Int.self, forKey: .namingRefreshWords) ?? 60
    }
}
