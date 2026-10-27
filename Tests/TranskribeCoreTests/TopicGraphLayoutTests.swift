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

    @Test func sideTopicsUseRowsBelowTheirParent() throws {
        var graph = TopicGraph(meetingId: UUID())
        let parent = try add(.new, at: 0, to: &graph)
        let side = try add(.side(parent), at: 10, to: &graph)
        let nested = try add(.side(side), at: 20, to: &graph)
        let sibling = try add(.side(parent), at: 30, to: &graph)
        let nextMain = try add(.new, at: 40, to: &graph)

        let layout = TopicGraphLayout(graph: graph)

        #expect(layout.cards.map(\.id) == [parent, side, nested, sibling, nextMain])
        #expect(layout.cards.map(\.row) == [0, 1, 2, 3, 0])
        #expect(layout.cards.map(\.frame.minY) == [32, 236, 440, 644, 32])
        for (index, card) in layout.cards.enumerated() {
            #expect(layout.cards.dropFirst(index + 1).allSatisfy { !card.frame.intersects($0.frame) })
        }
        #expect(layout.size == CGSize(width: 1456, height: 816))
    }

    private func add(_ route: TopicRoute, at start: Double, to graph: inout TopicGraph) throws -> String {
        try #require(try graph.apply(.init(route: route, points: [
            .init(track: 0, start: start, end: start + 1, text: "Topic at \(start)"),
        ])))
    }
}
