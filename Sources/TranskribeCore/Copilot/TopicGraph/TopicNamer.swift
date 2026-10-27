import Foundation

public struct TopicName: Decodable, Equatable, Sendable {
    public let label: String
    public let summary: String
}

public actor TopicNamer {
    private struct TopicKey: Hashable {
        let meetingId: UUID
        let topicId: String
    }

    private let provider: any AIProvider
    private let model: AIModel
    private let settings: TopicGraphSettings
    private var attemptedWordCounts: [TopicKey: Int] = [:]

    public init(provider: any AIProvider, model: AIModel, settings: TopicGraphSettings = .default) {
        self.provider = provider
        self.model = model
        self.settings = settings
    }

    /// Apply a returned name with TopicGraph.setName. Errors leave the graph unchanged.
    public func name(topicId: String, in graph: TopicGraph) async throws -> TopicName? {
        guard graph.topics.contains(where: { $0.id == topicId }) else { throw TopicGraphError.unknownTopic }
        let points = graph.points.filter { $0.topicId == topicId }
        let key = TopicKey(meetingId: graph.meetingId, topicId: topicId)
        let wordCount = points.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        if let previous = attemptedWordCounts[key], wordCount - previous < max(1, settings.namingRefreshWords) {
            return nil
        }
        // Count new words from each attempt, including a failed attempt.
        attemptedWordCounts[key] = wordCount
        let message = try TopicNamerPrompt.message(points: points)
        let response = try await AIStreaming.collect(provider.stream(
            model: model, system: TopicNamerPrompt.system, messages: [message]
        ))
        guard let name = try? JSONDecoder().decode(TopicName.self, from: Data(response.utf8)) else {
            throw AIError("The topic namer received invalid JSON.")
        }
        return name
    }
}
