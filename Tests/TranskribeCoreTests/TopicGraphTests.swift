import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphTests {
    @Test func firstCommittedBatchCreatesTopicAndPreservesTrackIdentity() throws {
        let meetingId = UUID()
        var graph = TopicGraph(meetingId: meetingId)
        let topicId = try #require(try graph.apply(.init(route: .continue, points: [
            .init(track: 0, start: 1, end: 4, text: "Microphone", speaker: 0),
            .init(track: 1, start: 1, end: 5, text: "System", speaker: 2, kind: .question),
        ])))

        #expect(graph.version == 1)
        #expect(graph.meetingId == meetingId)
        #expect(graph.currentTopicId == topicId)
        #expect(graph.topics.count == 1)
        #expect(graph.points.count == 2)
        #expect(Set(graph.points.map(\.id)).count == 2)
        #expect(graph.points.map(\.track) == [0, 1])
        #expect(graph.points.map(\.topicId) == [topicId, topicId])
        #expect(graph.points.last?.kind == .question)
        #expect(graph.topics.first?.firstSec == 1)
        #expect(graph.topics.first?.lastSec == 5)
        #expect(graph.topics.first?.totalSec == 7)
        #expect(graph.untilSec == 5)
        #expect(graph.edges.isEmpty)
    }

    @Test func shiftsCreateTopicsAndReturnsOnlyTargetEarlierTopics() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try #require(try graph.apply(batch(.new, start: 0)))
        let second = try #require(try graph.apply(batch(.new, start: 10)))
        let third = try #require(try graph.apply(batch(.new, start: 20)))
        #expect(Set([first, second, third]).count == 3)
        #expect(graph.edges.map(\.type) == [.shift, .shift])
        #expect(graph.edges.last?.from == second)
        #expect(graph.edges.last?.to == third)

        try graph.apply(batch(.returnTo(second), start: 30, confidence: 0.82))
        #expect(graph.currentTopicId == second)
        #expect(graph.edges.last?.type == .return)
        #expect(graph.edges.last?.from == third)
        #expect(graph.edges.last?.to == second)
        #expect(graph.edges.last?.atSec == 30)
        #expect(graph.edges.last?.pointId == graph.points.last?.id)
        #expect(graph.edges.last?.confidence == 0.82)
        #expect(graph.topics[1].firstSec == 10)
        #expect(graph.topics[1].lastSec == 32)
        #expect(graph.topics[1].totalSec == 4)

        let before = graph
        for target in [second, third, "missing"] {
            #expect(throws: (any Error).self) {
                try graph.apply(batch(.returnTo(target), start: 40))
            }
            #expect(graph == before)
        }
        try graph.apply(batch(.returnTo(first), start: 50))
        #expect(graph.currentTopicId == first)
    }

    @Test func sideTopicsKeepTheirParentAndMergeIntoParentOrEarlierTopic() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try #require(try graph.apply(batch(.new, start: 0)))
        let second = try #require(try graph.apply(batch(.new, start: 10)))
        let child = try #require(try graph.apply(batch(.side(first), start: 20)))
        #expect(graph.topics.last?.parentId == first)
        #expect(graph.edges.last?.type == .branch)
        #expect(graph.edges.last?.from == first)
        #expect(graph.edges.last?.to == child)
        try graph.apply(batch(.merge(second), start: 30))
        #expect(graph.currentTopicId == second)
        #expect(graph.edges.last?.type == .merge)
        #expect(graph.edges.last?.from == child)
        #expect(graph.topics.first { $0.id == child }?.status == .resolved)

        let nextChild = try #require(try graph.apply(batch(.side(second), start: 40)))
        let later = try #require(try graph.apply(batch(.new, start: 50)))
        try graph.apply(batch(.returnTo(nextChild), start: 60))
        let before = graph
        for route: TopicRoute in [.merge(later), .merge(nextChild), .merge("missing"),
                                   .side("missing"), .side(child)] {
            #expect(throws: (any Error).self) { try graph.apply(batch(route, start: 70)) }
            #expect(graph == before)
        }
        try graph.apply(batch(.merge(second), start: 80))
        #expect(graph.currentTopicId == second)
        #expect(graph.topics.first { $0.id == nextChild }?.status == .resolved)
    }

    @Test func repeatedRangesNeverCreatePointsTopicsOrEdgesAgain() throws {
        var graph = TopicGraph(meetingId: UUID())
        let microphone = TopicPointInput(track: 0, start: 2, end: 6, text: "First")
        let system = TopicPointInput(track: 1, start: 2, end: 6, text: "Second")
        try graph.apply(.init(route: .new, points: [microphone, microphone, system]))
        #expect(graph.points.count == 2)
        #expect(graph.topics.first?.totalSec == 8)
        let original = graph
        #expect(try graph.apply(.init(route: .new, points: [microphone, system])) == nil)
        #expect(graph == original)

        try graph.apply(.init(route: .new, points: [microphone,
            .init(track: 0, start: 2, end: 7, text: "Different end")]))
        #expect(graph.topics.count == 2)
        #expect(graph.points.count == 3)
        #expect(graph.edges.count == 1)
        #expect(graph.points.last?.text == "Different end")
        #expect(graph.topics.last?.totalSec == 5)
        let afterShift = graph
        try graph.apply(.init(route: .continue, points: [microphone]))
        #expect(graph == afterShift)
        try graph.apply(.init(route: .new, points: []))
        #expect(graph == afterShift)
    }

    @Test func invalidPointsOrConfidenceRejectTheWholeProposal() throws {
        var graph = TopicGraph(meetingId: UUID())
        try graph.apply(batch(.new, start: 10))
        let before = graph
        let invalid: [TopicPointInput] = [
            .init(track: -1, start: 1, end: 2, text: "Invalid track"),
            .init(track: 0, start: -1, end: 2, text: "Negative time"),
            .init(track: 0, start: 3, end: 2, text: "Reversed range"),
            .init(track: 0, start: .nan, end: 2, text: "Invalid start"),
            .init(track: 0, start: 1, end: .infinity, text: "Invalid end"),
        ]
        for point in invalid {
            #expect(throws: (any Error).self) {
                try graph.apply(.init(route: .new, points: [
                    .init(track: 0, start: 20, end: 21, text: "Valid"), point,
                ]))
            }
            #expect(graph == before)
        }
        for confidence in [-0.1, 1.1, Double.nan, Double.infinity] {
            #expect(throws: (any Error).self) { try graph.apply(batch(.new, start: 30, confidence: confidence)) }
            #expect(graph == before)
        }
    }

    @Test func topicNamesUseOneLineAndCapUnicodeCharacterLengths() throws {
        var graph = TopicGraph(meetingId: UUID())
        let topicId = try #require(try graph.apply(.init(route: .new, points: [
            .init(track: 0, start: 0, end: 1, text: String(repeating: "👩🏽‍💻", count: 100)),
        ])))
        #expect(graph.topics.first?.label.count == 80)
        try graph.setName(topicId: topicId, label: String(repeating: "é", count: 100),
                          summary: String(repeating: "👩🏽‍💻", count: 300))
        #expect(graph.topics.first?.label == String(repeating: "é", count: 80))
        #expect(graph.topics.first?.summary == String(repeating: "👩🏽‍💻", count: 240))
        try graph.setName(topicId: topicId, label: "  Pricing\n options  ", summary: " One\tline. ")
        #expect(graph.topics.first?.label == "Pricing options")
        #expect(graph.topics.first?.summary == "One line.")
        let before = graph
        #expect(throws: (any Error).self) { try graph.setName(topicId: topicId, label: " \n ", summary: "") }
        #expect(throws: (any Error).self) { try graph.setName(topicId: "missing", label: "Name", summary: "") }
        #expect(graph == before)
    }

    private func batch(_ route: TopicRoute, start: TimeInterval, confidence: Double? = nil) -> TopicGraphProposal {
        .init(route: route, points: [.init(track: 0, start: start, end: start + 2, text: "Topic at \(start)")],
              confidence: confidence)
    }
}
