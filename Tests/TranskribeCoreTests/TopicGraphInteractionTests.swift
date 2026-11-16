import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphInteractionTests {
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
