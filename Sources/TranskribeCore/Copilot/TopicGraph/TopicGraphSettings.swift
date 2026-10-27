import Foundation

public struct TopicGraphSettings: Codable, Equatable, Sendable {
    public var namingRefreshWords: Int

    public static let `default` = TopicGraphSettings()

    public init(namingRefreshWords: Int = 60) {
        self.namingRefreshWords = namingRefreshWords
    }
}
