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
        #expect(layout.size.width == 880)
        #expect(layout.size.height >= 204)
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
        #expect(layout.size.width == 1456)
        #expect(layout.size.height >= 816)
    }

    @Test func shiftAndBranchPathsConnectCardBoundaries() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try add(.new, at: 10, to: &graph)
        let side = try add(.side(second), at: 20, to: &graph)

        let layout = TopicGraphLayout(graph: graph)

        #expect(layout.edges.map(\.id) == graph.edges.map(\.id))
        #expect(layout.edges.map(\.type) == [.shift, .branch])
        #expect(layout.edges.map(\.from) == [first, second])
        #expect(layout.edges.map(\.to) == [second, side])
        #expect(layout.edges[0].waypoints == [CGPoint(x: 272, y: 102), CGPoint(x: 320, y: 102)])
        #expect(layout.edges[1].waypoints == [
            CGPoint(x: 440, y: 172), CGPoint(x: 440, y: 204),
            CGPoint(x: 584, y: 204), CGPoint(x: 584, y: 306), CGPoint(x: 608, y: 306),
        ])
    }

    @Test(arguments: [TopicEdgeType.return, .merge])
    func returnsAndMergesTravelBackWithoutMovingCards(type: TopicEdgeType) throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let parent = try add(.new, at: 10, to: &graph)
        let side = try add(.side(parent), at: 20, to: &graph)
        let before = TopicGraphLayout(graph: graph)
        let target = type == .return ? first : parent
        try add(type == .return ? .returnTo(target) : .merge(target), at: 30, to: &graph)

        let layout = TopicGraphLayout(graph: graph)
        let edge = try #require(layout.edges.last)

        #expect(layout.cards == before.cards)
        #expect(edge.id == graph.edges.last?.id)
        #expect(edge.type == type)
        #expect(edge.from == side)
        #expect(edge.to == target)
        #expect(edge.waypoints.first == CGPoint(x: 848, y: 306))
        #expect(edge.waypoints.last == CGPoint(x: type == .return ? 32 : 320, y: 102))
        #expect(edge.waypoints.contains { $0.y < 32 })
        #expect(zip(edge.waypoints, edge.waypoints.dropFirst()).allSatisfy {
            $0.x == $1.x || $0.y == $1.y
        })
    }

    @Test func longShiftsAndShiftsFromSideRowsAvoidCards() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try add(.new, at: 10, to: &graph)
        try add(.side(second), at: 20, to: &graph)
        try add(.new, at: 30, to: &graph)
        try add(.returnTo(first), at: 40, to: &graph)
        try add(.new, at: 50, to: &graph)

        let layout = TopicGraphLayout(graph: graph)

        for edge in layout.edges {
            #expect(edge.waypoints.allSatisfy {
                $0.x >= 0 && $0.y >= 0 && $0.x < layout.size.width && $0.y < layout.size.height
            })
            for (start, end) in zip(edge.waypoints, edge.waypoints.dropFirst()) {
                #expect(start.x == end.x || start.y == end.y)
                #expect(layout.cards.allSatisfy { !crossesInterior(from: start, to: end, of: $0.frame) })
            }
        }
    }

    @Test(arguments: [false, true])
    func draftFollowsTheEndOfTheCurrentRow(afterReturn: Bool) throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try add(.new, at: 10, to: &graph)
        try add(.side(second), at: 20, to: &graph)
        if afterReturn { try add(.returnTo(first), at: 30, to: &graph) }
        graph.draft = "Pending words"

        let layout = TopicGraphLayout(graph: graph)
        let draft = try #require(layout.draftCard)

        #expect(draft.topicId == graph.currentTopicId)
        #expect(draft.row == (afterReturn ? 0 : 1))
        #expect(draft.frame == CGRect(x: afterReturn ? 608 : 896, y: afterReturn ? 32 : 236,
                                      width: 240, height: 140))
        #expect(layout.cards.count == 3)
        #expect(layout.cards.allSatisfy { !draft.frame.intersects($0.frame) })
        #expect(layout.size.width > draft.frame.maxX)
        #expect(layout.size.height > draft.frame.maxY)
    }

    @Test func emptyGraphShowsOnlyANonemptyDraft() throws {
        var graph = TopicGraph(meetingId: UUID())
        for text in ["", " \n\t"] {
            graph.draft = text
            let layout = TopicGraphLayout(graph: graph)
            #expect(layout.cards.isEmpty)
            #expect(layout.edges.isEmpty)
            #expect(layout.draftCard == nil)
            #expect(layout.size == .zero)
        }

        graph.draft = "The first pending words"
        let layout = TopicGraphLayout(graph: graph)
        let draft = try #require(layout.draftCard)
        #expect(draft.topicId == nil)
        #expect(draft.row == 0)
        #expect(draft.frame == CGRect(x: 32, y: 32, width: 240, height: 140))
        #expect(layout.size == CGSize(width: 304, height: 204))
    }

    @Test func meetingOffsetsOrderTopicsAndEqualTimesKeepCreationOrder() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try #require(try graph.apply(.init(route: .new, points: [
            .init(track: 1, start: 0, end: 1, text: "System audio"),
        ])))
        #expect(TopicGraphLayout(graph: graph).cards.map(\.id) == [first, second])

        try graph.reconcileTimeline(trackOffsets: [0: 60, 1: 0],
                                    meetingStartedAt: Date(timeIntervalSince1970: 1_000))

        #expect(TopicGraphLayout(graph: graph).cards.map(\.id) == [second, first])
    }

    @Test func repeatedAndReloadedGraphsGiveTheSameLayout() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try add(.new, at: 10, to: &graph)
        try add(.side(second), at: 20, to: &graph)
        try add(.returnTo(first), at: 30, to: &graph)
        try add(.side(first), at: 40, to: &graph)
        try add(.merge(first), at: 50, to: &graph)
        graph.draft = "Still speaking"
        let layout = TopicGraphLayout(graph: graph)

        for _ in 0..<10 {
            #expect(TopicGraphLayout(graph: graph) == layout)
        }
        var restored = try JSONDecoder().decode(TopicGraph.self, from: JSONEncoder().encode(graph))
        restored.draft = graph.draft
        #expect(TopicGraphLayout(graph: restored) == layout)
    }

    @Test func threeHundredPointsTakeLessThanFiftyMilliseconds() throws {
        var graph = TopicGraph(meetingId: UUID())
        for index in 0..<300 {
            try add(.new, at: Double(index * 10), to: &graph)
        }
        let start = ContinuousClock.now
        let layout = TopicGraphLayout(graph: graph)
        let elapsed = start.duration(to: .now)

        #expect(graph.points.count == 300)
        #expect(layout.cards.count == 300)
        #expect(layout.edges.count == 299)
        #expect(elapsed < .milliseconds(50))
        print("300-point layout duration: \(elapsed)")
    }

    private func add(_ route: TopicRoute, at start: Double, to graph: inout TopicGraph) throws -> String {
        try #require(try graph.apply(.init(route: route, points: [
            .init(track: 0, start: start, end: start + 1, text: "Topic at \(start)"),
        ])))
    }

    private func crossesInterior(from start: CGPoint, to end: CGPoint, of frame: CGRect) -> Bool {
        if start.x == end.x {
            return start.x > frame.minX && start.x < frame.maxX
                && max(start.y, end.y) > frame.minY && min(start.y, end.y) < frame.maxY
        }
        return start.y > frame.minY && start.y < frame.maxY
            && max(start.x, end.x) > frame.minX && min(start.x, end.x) < frame.maxX
    }
}
