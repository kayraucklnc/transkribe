import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicMapLayoutTests {
    private let padding = TopicMapLayout.padding

    @Test func emptyGraphsHaveNoNodes() {
        let layout = TopicMapLayout(graph: TopicGraph(meetingId: UUID()))

        #expect(layout.nodes.isEmpty)
        #expect(layout.links.isEmpty)
        #expect(layout.size == .zero)
    }

    @Test func mainTopicsRunLeftToRightOnOneSpine() throws {
        var graph = TopicGraph(meetingId: UUID())
        let ids = try (0..<3).map { try add(.new, at: Double($0 * 10), to: &graph) }

        let layout = TopicMapLayout(graph: graph)

        #expect(layout.nodes.map(\.id) == ids)
        #expect(Set(layout.nodes.map(\.frame.minY)) == [padding])
        let xs = layout.nodes.map(\.frame.minX)
        #expect(xs == xs.sorted())
        #expect(layout.links.map(\.kind) == [.spine, .spine])
        #expect(layout.links.map(\.to) == Array(ids.dropFirst()))
        #expect(layout.links.allSatisfy { $0.segments.count == 1 && $0.segments[0].start.y == $0.segments[0].end.y })
    }

    @Test func eachTopicAppearsOnceEvenAfterReturns() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        try add(.new, at: 10, to: &graph)
        try add(.returnTo(first), at: 20, to: &graph)
        try add(.new, at: 30, to: &graph)

        let layout = TopicMapLayout(graph: graph)

        #expect(layout.nodes.count == graph.topics.count)
        #expect(Set(layout.nodes.map(\.id)).count == graph.topics.count)
    }

    @Test func sideTopicsHangBelowTheirParentLikeAnOrgChart() throws {
        var graph = TopicGraph(meetingId: UUID())
        let parent = try add(.new, at: 0, to: &graph)
        let left = try add(.side(parent), at: 10, to: &graph)
        let nested = try add(.side(left), at: 20, to: &graph)
        try add(.merge(parent), at: 25, to: &graph)
        let right = try add(.side(parent), at: 30, to: &graph)
        let next = try add(.new, at: 40, to: &graph)

        let layout = TopicMapLayout(graph: graph)
        let frames = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame) })
        let p = try #require(frames[parent]), l = try #require(frames[left]), r = try #require(frames[right])
        let n = try #require(frames[nested]), m = try #require(frames[next])

        #expect(l.minY > p.maxY && r.minY == l.minY)
        #expect(n.minY > l.maxY)
        #expect(l.maxX < r.minX)
        // The parent sits centred over its side topics.
        #expect(abs(p.midX - (l.minX + r.maxX) / 2) < 0.5)
        #expect(m.minY == p.minY && m.minX > r.maxX)
        let branches = layout.links.filter { $0.kind == .branch }
        #expect(Set(branches.map(\.to)) == [left, nested, right])
        for branch in branches {
            let from = try #require(frames[branch.from]), to = try #require(frames[branch.to])
            #expect(branch.segments.first?.start == CGPoint(x: from.midX, y: from.maxY))
            #expect(branch.segments.last?.end == CGPoint(x: to.midX, y: to.minY))
        }
    }

    @Test func longMeetingsWrapOntoLinesWithinTheWidth() throws {
        let graph = try longMeeting()
        let width: CGFloat = 900

        let layout = TopicMapLayout(graph: graph, width: width)

        #expect(Set(layout.nodes.map(\.line)).count > 1)
        #expect(layout.nodes.allSatisfy { $0.frame.maxX + padding <= width })
        for (index, node) in layout.nodes.enumerated() {
            #expect(layout.nodes.dropFirst(index + 1).allSatisfy { !node.frame.intersects($0.frame) })
        }
        let breaks = layout.links.filter { link in
            layout.nodes.first { $0.id == link.from }?.line != layout.nodes.first { $0.id == link.to }?.line
        }
        #expect(!breaks.isEmpty && breaks.allSatisfy { $0.kind == .spine })
    }

    @Test func connectorsAreContinuousAndNeverCrossACard() throws {
        let layout = TopicMapLayout(graph: try longMeeting(), width: 900)

        for link in layout.links {
            for (a, b) in zip(link.segments, link.segments.dropFirst()) { #expect(a.end == b.start) }
            let interior = link.segments.flatMap { $0.samples() }.dropFirst().dropLast()
            for node in layout.nodes {
                #expect(interior.allSatisfy { !node.frame.insetBy(dx: 1, dy: 1).contains($0) },
                        "\(link.id) crosses \(node.id)")
            }
            #expect(link.segments.flatMap { $0.samples() }.allSatisfy {
                $0.x >= 0 && $0.y >= 0 && $0.x <= layout.size.width && $0.y <= layout.size.height
            })
        }
    }

    @Test func historyShrinksToCompactMainTopicsWithTheirSideTopicsHidden() throws {
        var graph = TopicGraph(meetingId: UUID())
        let old = try add(.new, at: 0, to: &graph)
        let oldSide = try add(.side(old), at: 10, to: &graph)
        try add(.merge(old), at: 20, to: &graph)
        let now = try add(.new, at: 30, to: &graph)
        let nowSide = try add(.side(now), at: 40, to: &graph)

        let layout = TopicMapLayout(graph: graph, width: 900, focus: [now, nowSide])
        let nodes = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0) })

        #expect(nodes[oldSide] == nil)
        #expect(nodes[old]?.isDormant == true)
        #expect(nodes[old]?.frame.size == TopicMapLayout.dormantSize)
        #expect(nodes[now]?.isDormant == false && nodes[nowSide] != nil)
        // Compact and full main topics share a centre line, so the spine stays straight.
        #expect(nodes[old]?.frame.midY == nodes[now]?.frame.midY)
        #expect(layout.links.allSatisfy { nodes[$0.from] != nil && nodes[$0.to] != nil })
        #expect(layout.links.contains { $0.kind == .spine && $0.from == old && $0.to == now })
    }

    @Test func withoutAFocusEveryTopicIsShownInFull() throws {
        let graph = try longMeeting()
        let layout = TopicMapLayout(graph: graph, width: 900)

        #expect(layout.nodes.count == graph.topics.count)
        #expect(layout.nodes.allSatisfy { !$0.isDormant })
    }

    @Test func pendingTextDoesNotChangeTheMap() throws {
        var graph = try longMeeting()
        let layout = TopicMapLayout(graph: graph, width: 900)
        graph.draft = "Still speaking"

        #expect(TopicMapLayout(graph: graph, width: 900) == layout)
    }

    @Test func threeHundredTopicsTakeLessThanFiftyMilliseconds() throws {
        var graph = TopicGraph(meetingId: UUID())
        for index in 0..<300 {
            try add(.new, at: Double(index * 10), to: &graph)
        }
        let start = ContinuousClock.now
        let layout = TopicMapLayout(graph: graph, width: 1_200)

        #expect(layout.nodes.count == 300)
        #expect(start.duration(to: .now) < .milliseconds(50))
    }

    private func longMeeting() throws -> TopicGraph {
        var graph = TopicGraph(meetingId: UUID())
        var time = 0.0
        func next() -> Double { time += 10; return time }
        let a = try add(.new, at: next(), to: &graph)
        let b = try add(.new, at: next(), to: &graph)
        let side = try add(.side(b), at: next(), to: &graph)
        try add(.side(side), at: next(), to: &graph)
        try add(.merge(b), at: next(), to: &graph)
        try add(.side(b), at: next(), to: &graph)
        try add(.merge(b), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        try add(.returnTo(a), at: next(), to: &graph)
        let c = try add(.new, at: next(), to: &graph)
        try add(.side(c), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
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
