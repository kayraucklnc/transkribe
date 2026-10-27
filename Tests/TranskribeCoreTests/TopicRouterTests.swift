import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicRouterTests {
    @Test func continuesWithOneRequestAndPreservesCommittedText() async throws {
        let client = TopicDecisionFake()
        let router = TopicRouter(client: client, model: .jev)
        var graph = TopicGraph(meetingId: UUID())
        let topicId = try #require(try graph.apply(.init(route: .new, points: [
            .init(track: 0, start: 0, end: 2, text: "Pricing"),
        ])))
        try graph.setName(topicId: topicId, label: "Pricing", summary: "Discuss the price.")
        let segments = [TopicPointInput(track: 1, start: 2, end: 4, text: "The price is ten.", speaker: 3)]

        let proposal = try #require(try await router.route(segments, in: graph))

        #expect(proposal.route == .continue)
        #expect(proposal.points == segments)
        #expect(proposal.confidence == 0.9)
        let requests = await client.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.model == .jev)
        #expect(Set(request.questions.keys) == ["route", "kind"])
        #expect(request.questions["route"]?.type == .choice)
        #expect(Set(request.questions["route"]?.criteria.keys.map { $0 } ?? [])
            == ["continue", "new", "side:\(topicId)"])
        #expect(Set(request.questions["kind"]?.criteria.keys.map { $0 } ?? [])
            == ["statement", "question", "decision", "action", "objection"])
        #expect(request.state.contains(topicId))
        #expect(request.state.contains("Pricing"))
        #expect(request.state.contains("Discuss the price."))
        #expect(request.state.contains("The price is ten."))
        try graph.apply(proposal)
        #expect(graph.currentTopicId == topicId)
        #expect(graph.points.last?.track == 1)
        #expect(graph.points.last?.speaker == 3)
    }
}

private struct TopicDecisionRequest: Encodable, Sendable {
    let model: DecisionModel
    let state: String
    let questions: [String: DecisionQuestion]
}

private actor TopicDecisionFake: DecisionClient {
    private(set) var requests: [TopicDecisionRequest] = []

    func decide(model: DecisionModel, state: String,
                questions: [String: DecisionQuestion]) async throws -> [String: DecisionAnswer] {
        requests.append(.init(model: model, state: state, questions: questions))
        return ["route": .init(type: .choice, choice: "continue", confidence: 0.9),
                "kind": .init(type: .choice, choice: "statement")]
    }
}
