import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphInteractionTests {
    @Test func hitTestFindsTopicsAndPointsAndIgnoresEmptySpace() throws {
        var graph = TopicGraph(meetingId: UUID())
        let topicId = try graph.apply(.init(route: .new, points: [
            .init(track: 0, start: 0, end: 5, text: "A point")
        ]))
        let topic = try #require(topicId)
        let point = try #require(graph.points.first)
        graph.draft = "Pending speech"
        let layout = TopicGraphLayout(graph: graph)
        let regions = TopicGraphInteraction.regions(in: layout) + [
            TopicGraphInteraction.Region(target: .point(point.id),
                frame: CGRect(x: 48, y: 112, width: 100, height: 24))
        ]

        #expect(TopicGraphInteraction.hitTest(at: CGPoint(x: 60, y: 60), regions: regions) == .topic(topic))
        #expect(TopicGraphInteraction.hitTest(at: CGPoint(x: 60, y: 120), regions: regions) == .point(point.id))
        #expect(TopicGraphInteraction.hitTest(at: .zero, regions: regions) == nil)
        #expect(TopicGraphInteraction.hitTest(at: CGPoint(x: 290, y: 60), regions: regions) == nil)
        #expect(TopicGraphInteraction.hitTest(at: CGPoint(x: 330, y: 60), regions: regions) == nil)
        #expect(TopicGraphInteraction.hitTest(at: CGPoint(x: CGFloat.infinity, y: 60), regions: regions) == nil)
    }

    @Test(arguments: [false, true])
    func hoverTouchesOnlyDirectNeighboursAndIncidentEdges(merges: Bool) throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try add(.new, at: 10, to: &graph)
        let side = try add(.side(second), at: 20, to: &graph)
        let remote = try add(.side(side), at: 30, to: &graph)
        _ = try add(merges ? .merge(second) : .returnTo(second), at: 40, to: &graph)

        let touches = TopicGraphInteraction.touches(topicId: second, in: graph)

        #expect(touches.topicIds == [first, second, side, remote])
        #expect(touches.edgeIds == [graph.edges[0].id, graph.edges[1].id, graph.edges[3].id])
        let leaf = TopicGraphInteraction.touches(topicId: first, in: graph)
        #expect(leaf.topicIds == [first, second])
        #expect(leaf.edgeIds == [graph.edges[0].id])
        #expect(TopicGraphInteraction.touches(topicId: "missing", in: graph).topicIds.isEmpty)
        #expect(TopicGraphInteraction.touches(topicId: "missing", in: graph).edgeIds.isEmpty)
    }

    @Test func jumpTargetsUseMeetingTimeForTwoTracksWithDifferentOffsets() throws {
        var graph = TopicGraph(meetingId: UUID())
        let id = try graph.apply(.init(route: .new, points: [
            .init(track: 0, start: 5, end: 9, text: "Microphone", speaker: 0),
            .init(track: 1, start: 5, end: 9, text: "System", speaker: 1)
        ]))
        let topic = try #require(id)
        let mic = graph.points[0], system = graph.points[1]
        try graph.reconcileTimeline(trackOffsets: [0: 20, 1: 3], meetingStartedAt: Date(timeIntervalSince1970: 0))

        #expect(TopicGraphInteraction.jumpTime(to: .point(mic.id), in: graph) == 25)
        #expect(TopicGraphInteraction.jumpTime(to: .point(system.id), in: graph) == 8)
        #expect(TopicGraphInteraction.jumpTime(to: .topic(topic), in: graph) == 8)
        #expect(TopicGraphInteraction.jumpTime(to: .point("missing"), in: graph) == nil)
        #expect(TopicGraphInteraction.jumpTime(to: .topic("missing"), in: graph) == nil)

        try graph.reconcileTimeline(trackOffsets: [0: 1, 1: 10], meetingStartedAt: Date(timeIntervalSince1970: 0))

        #expect(TopicGraphInteraction.jumpTime(to: .point(mic.id), in: graph) == 6)
        #expect(TopicGraphInteraction.jumpTime(to: .point(system.id), in: graph) == 15)
        #expect(TopicGraphInteraction.jumpTime(to: .topic(topic), in: graph) == 6)
        #expect(graph.points.map(\.start) == [5, 5])
    }

    private func add(_ route: TopicRoute, at start: TimeInterval, to graph: inout TopicGraph) throws -> String {
        let id = try graph.apply(.init(route: route, points: [
            .init(track: 0, start: start, end: start + 5, text: "Point at \(start)")
        ]))
        return try #require(id)
    }
}
