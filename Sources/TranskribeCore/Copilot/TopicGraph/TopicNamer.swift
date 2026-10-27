import Foundation

public struct TopicName: Decodable, Equatable, Sendable {
    public let label: String
    public let summary: String
}

public actor TopicNamer {
    private let provider: any AIProvider
    private let model: AIModel

    public init(provider: any AIProvider, model: AIModel) {
        self.provider = provider
        self.model = model
    }

    /// Apply a returned name with TopicGraph.setName. Errors leave the graph unchanged.
    public func name(topicId: String, in graph: TopicGraph) async throws -> TopicName? {
        guard graph.topics.contains(where: { $0.id == topicId }) else { throw TopicGraphError.unknownTopic }
        let points = graph.points.filter { $0.topicId == topicId }
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
