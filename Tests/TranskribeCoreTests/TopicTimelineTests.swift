import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicTimelineTests {
    @Test func emptyGraphsHaveNoRowsEvenWithPendingText() {
        var graph = TopicGraph(meetingId: UUID())
        graph.draft = "The first pending words"

        let timeline = TopicTimeline(graph: graph)

        #expect(timeline.rows.isEmpty)
        #expect(timeline.visits.isEmpty)
        #expect(timeline.end == 0)
    }

    @Test func eachMainTopicGetsARowInTheOrderItCameUp() throws {
        var graph = TopicGraph(meetingId: UUID())
        let ids = try [0, 30, 70].map { try add(.new, at: $0, to: &graph) }

        let timeline = TopicTimeline(graph: graph)

        #expect(timeline.rows.map(\.id) == ids)
        #expect(timeline.rows.allSatisfy { $0.depth == 0 && $0.visitCount == 1 })
        #expect(timeline.visits.map(\.row) == [0, 1, 2])
        #expect(timeline.visits.map(\.start) == [0, 30, 70])
        #expect(timeline.visits.map(\.end) == [30, 70, 71])
        #expect(timeline.end == 71)
        #expect(timeline.currentTopicId == ids[2])
    }

    @Test func sideTopicsSitDirectlyUnderTheTopicTheyBranchFrom() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let side = try add(.side(first), at: 10, to: &graph)
        let nested = try add(.side(side), at: 20, to: &graph)
        let second = try add(.new, at: 30, to: &graph)
        let late = try add(.side(first), at: 40, to: &graph)

        let timeline = TopicTimeline(graph: graph)

        // An outline: a side topic that comes up later still sits under its parent.
        #expect(timeline.rows.map(\.id) == [first, side, nested, late, second])
        #expect(timeline.rows.map(\.depth) == [0, 1, 2, 1, 0])
    }

    @Test func goingBackAddsAVisitOnTheExistingRow() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try add(.new, at: 20, to: &graph)
        try add(.returnTo(first), at: 50, to: &graph)

        let timeline = TopicTimeline(graph: graph)

        #expect(timeline.rows.count == 2)
        #expect(timeline.visits.map(\.topicId) == [first, second, first])
        #expect(timeline.visits.map(\.row) == [0, 1, 0])
        #expect(timeline.rows[0].visitCount == 2)
        #expect(timeline.rows[0].totalSec == 20 + 1)
        #expect(timeline.rows[1].totalSec == 30)
        #expect(timeline.currentTopicId == first)
    }

    @Test func mergingBackMarksTheSideTopicResolvedAndResumesTheParentRow() throws {
        var graph = TopicGraph(meetingId: UUID())
        let parent = try add(.new, at: 0, to: &graph)
        let side = try add(.side(parent), at: 10, to: &graph)
        try add(.merge(parent), at: 25, to: &graph)

        let timeline = TopicTimeline(graph: graph)

        #expect(timeline.visits.map(\.topicId) == [parent, side, parent])
        #expect(timeline.rows.first { $0.id == side }?.isResolved == true)
        #expect(timeline.rows.first { $0.id == parent }?.isResolved == false)
    }

    @Test func visitsFormOneUnbrokenPathForwardInTime() throws {
        let graph = try longMeeting()
        let timeline = TopicTimeline(graph: graph)

        #expect(timeline.visits.count == graph.edges.count + 1)
        for (previous, visit) in zip(timeline.visits, timeline.visits.dropFirst()) {
            #expect(visit.start == previous.end)
            #expect(visit.start >= previous.start)
        }
        #expect(timeline.visits.last?.end == timeline.end)
        let total = timeline.rows.map(\.totalSec).reduce(0, +)
        #expect(abs(total - (timeline.end - timeline.visits[0].start)) < 0.001)
    }

    @Test func pendingTextDoesNotChangeTheTimeline() throws {
        var graph = try longMeeting()
        let timeline = TopicTimeline(graph: graph)
        graph.draft = "Still speaking"

        #expect(TopicTimeline(graph: graph) == timeline)
    }

    @Test func theWholeMeetingWindowScalesToTheTrackWidth() throws {
        var graph = TopicGraph(meetingId: UUID())
        try add(.new, at: 0, to: &graph)
        try add(.new, at: 299, to: &graph)
        let timeline = TopicTimeline(graph: graph)

        let window = timeline.window(span: nil)

        #expect(timeline.end == 300)
        #expect(window == 0...300)
        #expect(timeline.x(for: 0, in: window, width: 600) == 0)
        #expect(timeline.x(for: 150, in: window, width: 600) == 300)
        #expect(timeline.x(for: 300, in: window, width: 600) == 600)
    }

    @Test func shortMeetingsUseAOneMinuteScale() throws {
        var graph = TopicGraph(meetingId: UUID())
        try add(.new, at: 0, to: &graph)
        let timeline = TopicTimeline(graph: graph)

        #expect(timeline.window(span: nil) == 0...60)
        #expect(timeline.window(span: 600) == 0...60)
    }

    @Test func aSpanSlidesWithTheConversationOnceTheMeetingIsLonger() throws {
        var graph = TopicGraph(meetingId: UUID())
        try add(.new, at: 0, to: &graph)
        try add(.new, at: 1_799, to: &graph)
        let timeline = TopicTimeline(graph: graph)

        let window = timeline.window(span: 600)

        #expect(window == 1_200...1_800)
        // Earlier time falls left of the track and is clipped by the view.
        #expect(timeline.x(for: 600, in: window, width: 600) < 0)
        #expect(timeline.x(for: 1_800, in: window, width: 600) == 600)
        #expect(timeline.window(span: 3_600) == 0...1_800)
    }

    @Test func rulerTicksUseRoundIntervalsInsideTheWindow() throws {
        var graph = TopicGraph(meetingId: UUID())
        try add(.new, at: 0, to: &graph)
        try add(.new, at: 2_699, to: &graph)
        let timeline = TopicTimeline(graph: graph)

        let whole = timeline.ticks(in: timeline.window(span: nil), width: 600, spacing: 72)
        let recent = timeline.ticks(in: timeline.window(span: 600), width: 600, spacing: 72)

        #expect(whole == stride(from: 0, through: 2_700, by: 600).map { $0 })
        #expect(recent == stride(from: 2_160, through: 2_700, by: 120).map { $0 })
        for ticks in [whole, recent] {
            for (a, b) in zip(ticks, ticks.dropFirst()) { #expect(b - a > 0) }
        }
    }

    @Test func topicsTheConversationMovedOnFromLeaveTheFocus() throws {
        var graph = TopicGraph(meetingId: UUID())
        let old = try add(.new, at: 0, to: &graph)
        let oldSide = try add(.side(old), at: 60, to: &graph)
        let middle = try add(.new, at: 600, to: &graph)
        let recent = try add(.new, at: 1_000, to: &graph)
        let recentSide = try add(.side(recent), at: 1_700, to: &graph)
        let timeline = TopicTimeline(graph: graph)

        let focused = timeline.focusedTopicIds(in: timeline.window(span: 600))

        #expect(focused == [recent, recentSide])
        #expect(!focused.contains(old) && !focused.contains(oldSide) && !focused.contains(middle))
        // The whole meeting keeps every topic in focus.
        #expect(timeline.focusedTopicIds(in: timeline.window(span: nil)).count == 5)
    }

    @Test func goingBackToATopicBringsItAndItsParentBackIntoFocus() throws {
        var graph = TopicGraph(meetingId: UUID())
        let old = try add(.new, at: 0, to: &graph)
        let oldSide = try add(.side(old), at: 60, to: &graph)
        try add(.new, at: 900, to: &graph)
        try add(.new, at: 1_200, to: &graph)
        try add(.returnTo(oldSide), at: 1_700, to: &graph)
        let timeline = TopicTimeline(graph: graph)

        let focused = timeline.focusedTopicIds(in: timeline.window(span: 600))

        #expect(focused.contains(oldSide))
        #expect(focused.contains(old))
        #expect(timeline.rows.first { $0.id == oldSide }?.parentId == old)
    }

    @Test func threeHundredTopicsTakeLessThanFiftyMilliseconds() throws {
        var graph = TopicGraph(meetingId: UUID())
        for index in 0..<300 {
            try add(.new, at: Double(index * 10), to: &graph)
        }
        let start = ContinuousClock.now
        let timeline = TopicTimeline(graph: graph)

        #expect(timeline.rows.count == 300)
        #expect(timeline.visits.count == 300)
        #expect(start.duration(to: .now) < .milliseconds(50))
    }

    private func longMeeting() throws -> TopicGraph {
        var graph = TopicGraph(meetingId: UUID())
        var time = 0.0
        func next() -> Double { time += 25; return time }
        let a = try add(.new, at: next(), to: &graph)
        let b = try add(.new, at: next(), to: &graph)
        try add(.side(b), at: next(), to: &graph)
        try add(.merge(b), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        try add(.returnTo(a), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        let d = try add(.new, at: next(), to: &graph)
        try add(.side(d), at: next(), to: &graph)
        try add(.returnTo(b), at: next(), to: &graph)
        try add(.returnTo(a), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        return graph
    }

    @discardableResult
    private func add(_ route: TopicRoute, at start: Double, to graph: inout TopicGraph) throws -> String {
        try #require(try graph.apply(.init(route: route, points: [
            .init(track: 0, start: start, end: start + 1, text: "Topic at \(start)"),
        ])))
    }
}
