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

    /// Call after committing points. Apply a returned name with TopicGraph.setName.
    /// Returns nil below the refresh threshold or for malformed output. Provider errors propagate.
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
        guard let name = try? JSONDecoder().decode(TopicName.self, from: Data(response.utf8)),
              !name.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return TopicName(label: Self.singleLine(name.label, limit: TopicGraph.maxLabelLength),
                         summary: Self.singleLine(name.summary, limit: TopicGraph.maxSummaryLength))
    }

    private static func singleLine(_ text: String, limit: Int) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
    }
}
