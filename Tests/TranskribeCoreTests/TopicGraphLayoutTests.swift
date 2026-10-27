import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphLayoutTests {
    @Test func mainThreadUsesOneRowInMeetingTimeOrder() throws {
        var graph = TopicGraph(meetingId: UUID())
        let later = try add(.new, at: 20, to: &graph)
        let earlier = try add(.new, at: 0, to: &graph)
        let last = try add(.new, at: 40, to: &graph)

        let layout = TopicGraphLayout(graph: graph)

        #expect(layout.cards.map(\.id) == [earlier, later, last])
        #expect(layout.cards.map(\.row) == [0, 0, 0])
        #expect(layout.cards.map(\.frame.minY) == [32, 32, 32])
        #expect(layout.cards.map(\.frame.minX) == [32, 320, 608])
        #expect(layout.cards.allSatisfy { $0.frame.size == CGSize(width: 240, height: 140) })
        #expect(layout.size == CGSize(width: 880, height: 204))
    }

    private func add(_ route: TopicRoute, at start: Double, to graph: inout TopicGraph) throws -> String {
        try #require(try graph.apply(.init(route: route, points: [
            .init(track: 0, start: start, end: start + 1, text: "Topic at \(start)"),
        ])))
    }
}
