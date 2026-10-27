import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicNamerTests {
    @Test func namesANewTopicFromItsCommittedPoints() async throws {
        let provider = FakeAIProvider(budget: 100_000) { _ in
            #"{"label":"Pricing","summary":"Set the launch price."}"#
        }
        let namer = TopicNamer(provider: provider, model: provider.models[0])
        var graph = TopicGraph(meetingId: UUID())
        let topicId = try #require(try graph.apply(.init(route: .new, points: [
            .init(track: 0, start: 0, end: 2, text: "The launch price is ten."),
        ])))
        #expect(graph.topics.first?.label == "The launch price is ten.")

        let name = try #require(try await namer.name(topicId: topicId, in: graph))
        try graph.setName(topicId: topicId, label: name.label, summary: name.summary)

        #expect(graph.topics.first?.label == "Pricing")
        #expect(graph.topics.first?.summary == "Set the launch price.")
        let call = try #require(provider.calls.first)
        #expect(call.messages.count == 1)
        #expect(call.messages.first?.role == .user)
        #expect(call.messages.first?.text.contains("The launch price is ten.") == true)
    }
}
