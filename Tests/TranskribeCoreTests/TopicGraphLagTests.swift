import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphLagTests {
    @Test func recordsEveryRoutedBatchAndKeepsNamingOptional() throws {
        let speech = Date(timeIntervalSince1970: 100)
        let records = [
            TopicGraphLagRecord(pointIds: ["a"], speechEndedAt: speech,
                                committedAt: speech.addingTimeInterval(3), routedAt: speech.addingTimeInterval(5)),
            TopicGraphLagRecord(pointIds: ["b"], speechEndedAt: speech,
                                committedAt: speech.addingTimeInterval(7), routedAt: speech.addingTimeInterval(15),
                                namedAt: speech.addingTimeInterval(18)),
        ]
        #expect(records[0].sttLag == 3)
        #expect(records[0].graphLag == 5)
        #expect(records[0].namedLag == nil)
        #expect(records[1].namedLag == 18)
        let summary = TopicGraphLagSummary(records: records)
        #expect(summary.sttMedian == 5)
        #expect(summary.sttP90 == 7)
        #expect(summary.graphMedian == 10)
        #expect(summary.graphP90 == 15)
        #expect(summary.namedMedian == 18)
        #expect(summary.namedSampleCount == 1)
        #expect(summary.routedSampleCount == 2)
        #expect(try JSONDecoder().decode([TopicGraphLagRecord].self,
                                       from: JSONEncoder().encode(records)) == records)
    }
}

@Suite struct TopicGraphTimelineTests {
    @Test func oldGraphsDecodeWithoutTimingMetadataAndInvalidLagReferencesFail() throws {
        var graph = TopicGraph(meetingId: UUID())
        try graph.apply(.init(route: .new, points: [.init(track: 0, start: 1, end: 2, text: "First")]))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)) as? [String: Any])
        for key in ["trackOffsets", "meetingStartedAt", "lagRecords"] { json[key] = nil }
        let old = try JSONDecoder().decode(TopicGraph.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old == graph)
        graph.lagRecords = [.init(pointIds: ["missing"], speechEndedAt: Date(), committedAt: Date(), routedAt: Date())]
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TopicGraph.self, from: JSONEncoder().encode(graph))
        }
    }

    @Test func reconcilesMeetingTimesWithoutChangingTrackKeysOrLagMilestones() throws {
        let start = Date(timeIntervalSince1970: 100)
        var graph = TopicGraph(meetingId: UUID())
        try graph.apply(.init(route: .new, points: [.init(track: 0, start: 1, end: 3, text: "First")]))
        try graph.apply(.init(route: .new, points: [.init(track: 1, start: 1, end: 3, text: "Second")]))
        graph.lagRecords = [.init(pointIds: [graph.points[1].id], speechEndedAt: start.addingTimeInterval(3),
                                  committedAt: start.addingTimeInterval(10), routedAt: start.addingTimeInterval(12))]
        try graph.reconcileTimeline(trackOffsets: [0: 0, 1: 5], meetingStartedAt: start)
        #expect(graph.points.map(\.start) == [1, 1])
        #expect(graph.topics.map(\.firstSec) == [1, 6])
        #expect(graph.topics.map(\.lastSec) == [3, 8])
        #expect(graph.edges.first?.atSec == 6)
        #expect(graph.untilSec == 8)
        #expect(graph.lagRecords.first?.sttLag == 2)
        #expect(graph.lagRecords.first?.graphLag == 4)
        #expect(graph.meetingTime(for: graph.points[1]) == 6)
        #expect(try graph.apply(.init(route: .continue, points: [
            .init(track: 1, start: 1, end: 3, text: "Repeated"),
        ])) == nil)
        #expect(graph.points.count == 2)
        #expect(try JSONDecoder().decode(TopicGraph.self, from: JSONEncoder().encode(graph)) == graph)
    }
}
