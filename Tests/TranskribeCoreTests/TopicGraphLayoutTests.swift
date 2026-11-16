import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphLayoutTests {
    private let card = TopicGraphLayout.cardSize
    private let step = TopicGraphLayout.cardSize.width + TopicGraphLayout.columnGap
    private let padding = TopicGraphLayout.padding

    @Test func mainTopicsFollowTheConversationOnOneRow() throws {
        var graph = TopicGraph(meetingId: UUID())
        let ids = try (0..<3).map { try add(.new, at: Double($0 * 10), to: &graph) }

        let layout = TopicGraphLayout(graph: graph)

        #expect(layout.cards.map(\.id) == ids)
        #expect(layout.cards.map(\.topicId) == ids)
        #expect(layout.cards.map(\.row) == [0, 0, 0])
        #expect(layout.cards.allSatisfy { $0.frame.minY == padding && $0.frame.size == card && $0.revisit == nil })
        #expect(layout.cards.map(\.frame.minX) == [padding, padding + step, padding + 2 * step])
        #expect(layout.edges.allSatisfy { $0.start.y == $0.end.y && $0.segments.count == 1 })
        #expect(layout.currentCardId == ids[2])
        #expect(layout.size == CGSize(width: padding + 2 * step + card.width + padding,
                                      height: padding + card.height + padding))
    }

    @Test func sideTopicsNestOneRowBelowTheirParent() throws {
        var graph = TopicGraph(meetingId: UUID())
        let parent = try add(.new, at: 0, to: &graph)
        let side = try add(.side(parent), at: 10, to: &graph)
        let nested = try add(.side(side), at: 20, to: &graph)
        let sibling = try add(.side(parent), at: 30, to: &graph)
        let nextMain = try add(.new, at: 40, to: &graph)

        let layout = TopicGraphLayout(graph: graph)

        #expect(layout.cards.map(\.topicId) == [parent, side, nested, sibling, nextMain])
        // Siblings share a row: a new side topic does not open a new row.
        #expect(layout.cards.map(\.row) == [0, 1, 2, 1, 0])
        for (index, card) in layout.cards.enumerated() {
            #expect(layout.cards.dropFirst(index + 1).allSatisfy { !card.frame.intersects($0.frame) })
        }
    }

    @Test(arguments: [TopicEdgeType.return, .merge])
    func goingBackAddsARevisitCardInsteadOfALinkBackwards(type: TopicEdgeType) throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let parent = try add(.new, at: 10, to: &graph)
        try add(.side(parent), at: 20, to: &graph)
        let target = type == .return ? first : parent
        try add(type == .return ? .returnTo(target) : .merge(target), at: 30, to: &graph)
        let next = try add(.new, at: 40, to: &graph)

        let layout = TopicGraphLayout(graph: graph)
        let revisit = try #require(layout.cards.first { $0.revisit != nil })
        let back = try #require(graph.edges.first { $0.type == type })

        #expect(layout.cards.count == graph.topics.count + 1)
        #expect(revisit.revisit == type)
        #expect(revisit.topicId == target)
        #expect(revisit.isCompact)
        #expect(revisit.row == 0)
        #expect(layout.edges.first { $0.id == back.id }?.to == revisit.id)
        // The conversation continues from the revisit, not from the original card.
        #expect(layout.edges.last?.from == revisit.id)
        #expect(layout.edges.last?.to == next)
        #expect(layout.currentCardId == next)
    }

    @Test func everyLinkJoinsNeighbouringColumnsLeftToRight() throws {
        let layout = TopicGraphLayout(graph: try busyGraph())
        let frames = Dictionary(uniqueKeysWithValues: layout.cards.map { ($0.id, $0.frame) })

        for edge in layout.edges {
            let source = try #require(frames[edge.from]), target = try #require(frames[edge.to])
            #expect(target.minX - source.maxX == TopicGraphLayout.columnGap)
            #expect(edge.start == CGPoint(x: source.maxX, y: source.midY))
            #expect(edge.end == CGPoint(x: target.minX, y: target.midY))
            #expect(edge.segments.flatMap { $0.samples() }.allSatisfy { $0.x >= source.maxX && $0.x <= target.minX })
        }
        let xs = layout.cards.map(\.frame.minX)
        #expect(xs == xs.sorted())
    }

    @Test func linksAreSmoothCurvesBetweenRows() throws {
        var graph = TopicGraph(meetingId: UUID())
        let parent = try add(.new, at: 0, to: &graph)
        try add(.side(parent), at: 10, to: &graph)

        let curve = try #require(TopicGraphLayout(graph: graph).edges.first?.segments.first)

        #expect(curve.end.y > curve.start.y)
        // Leaves and arrives horizontally: an S-curve, not a right angle.
        #expect(curve.control1.y == curve.start.y)
        #expect(curve.control2.y == curve.end.y)
        #expect(abs(curve.endAngle) < 0.001)
    }

    @Test func longMeetingsWrapOntoNewLinesWithinTheWidth() throws {
        let graph = try busyGraph()
        let width: CGFloat = 900
        let layout = TopicGraphLayout(graph: graph, width: width)
        let unwrapped = TopicGraphLayout(graph: graph)

        #expect(layout.cards.map(\.id) == unwrapped.cards.map(\.id))
        #expect(Set(layout.cards.map(\.line)).count > 1)
        #expect(layout.cards.allSatisfy { $0.frame.maxX + padding <= width })
        #expect(layout.size.width <= width)
        // Lines read like text: left to right, then the next line below.
        for (previous, card) in zip(layout.cards, layout.cards.dropFirst()) {
            #expect(card.line == previous.line ? card.frame.minX > previous.frame.maxX : card.line == previous.line + 1)
            if card.line != previous.line { #expect(card.frame.minX == padding) }
        }
        let lineBottoms = Dictionary(grouping: layout.cards, by: \.line).mapValues { $0.map(\.frame.maxY).max() ?? 0 }
        let lineTops = Dictionary(grouping: layout.cards, by: \.line).mapValues { $0.map(\.frame.minY).min() ?? 0 }
        for line in lineTops.keys where line > 0 {
            #expect(lineTops[line]! > lineBottoms[line - 1]!)
        }
    }

    @Test func lineBreaksUseOneRoundedConnectorThatAvoidsCards() throws {
        let layout = TopicGraphLayout(graph: try busyGraph(), width: 900)
        let lines = Dictionary(uniqueKeysWithValues: layout.cards.map { ($0.id, $0.line) })
        let breaks = layout.edges.filter { lines[$0.from] != lines[$0.to] }

        #expect(!breaks.isEmpty)
        for edge in breaks {
            #expect(edge.segments.count == 5)
            for (a, b) in zip(edge.segments, edge.segments.dropFirst()) { #expect(a.end == b.start) }
            #expect(abs(edge.endAngle - .pi / 2) < 0.001)
        }
        for edge in layout.edges {
            let interior = edge.segments.flatMap { $0.samples() }.dropFirst().dropLast()
            for card in layout.cards {
                #expect(interior.allSatisfy { !card.frame.insetBy(dx: 1, dy: 1).contains($0) })
            }
        }
    }

    @Test func sideTopicsWrapTogetherWithTheCardTheyLeaveFrom() throws {
        var graph = TopicGraph(meetingId: UUID())
        try add(.new, at: 0, to: &graph)
        let parent = try add(.new, at: 10, to: &graph)
        let side = try add(.side(parent), at: 20, to: &graph)
        // Room for two full cards and part of a third: the side topic would not fit after its parent.
        let width = padding * 2 + card.width * 2 + TopicGraphLayout.columnGap + 100

        let layout = TopicGraphLayout(graph: graph, width: width)
        let lines = Dictionary(uniqueKeysWithValues: layout.cards.map { ($0.id, $0.line) })

        #expect(lines[parent] == 1)
        #expect(lines[side] == 1)
    }

    @Test func narrowWidthsStillPlaceOneCardPerLine() throws {
        let layout = TopicGraphLayout(graph: try busyGraph(), width: 100)

        #expect(layout.cards.enumerated().allSatisfy { $0.element.line == $0.offset })
        #expect(layout.cards.allSatisfy { $0.frame.minX == padding })
        // Wider than the pane: the canvas scrolls sideways instead of clipping cards.
        #expect(layout.size.width > 100)
    }

    @Test func shortGraphsKeepEveryCardFullSize() throws {
        var graph = TopicGraph(meetingId: UUID())
        for index in 0..<TopicGraphLayout.collapseThreshold {
            try add(.new, at: Double(index * 10), to: &graph)
        }

        #expect(TopicGraphLayout.collapsedTopicIds(in: graph).isEmpty)
        #expect(TopicGraphLayout(graph: graph).cards.allSatisfy { !$0.isCompact })
    }

    @Test func longGraphsCollapseOlderTopicsButKeepTheCurrentNeighbourhood() throws {
        var graph = TopicGraph(meetingId: UUID())
        var ids: [String] = []
        for index in 0..<12 {
            ids.append(try add(.new, at: Double(index * 10), to: &graph))
        }
        try add(.returnTo(ids[2]), at: 200, to: &graph)

        let collapsed = TopicGraphLayout.collapsedTopicIds(in: graph)
        let layout = TopicGraphLayout(graph: graph)

        // Current topic and its neighbours (1, 3 and the last topic it returned from).
        #expect(!collapsed.contains(ids[2]))
        #expect(!collapsed.contains(ids[1]) && !collapsed.contains(ids[3]) && !collapsed.contains(ids[11]))
        // The most recently active topics.
        #expect(!collapsed.contains(ids[10]) && !collapsed.contains(ids[9]))
        #expect(collapsed.contains(ids[0]) && collapsed.contains(ids[5]))
        for card in layout.cards where card.revisit == nil {
            #expect(card.isCompact == collapsed.contains(card.topicId))
            #expect(card.frame.size == (card.isCompact ? TopicGraphLayout.compactSize : TopicGraphLayout.cardSize))
        }
    }

    @Test func emptyGraphsHaveNoCardsEvenWithPendingText() throws {
        var graph = TopicGraph(meetingId: UUID())
        graph.draft = "The first pending words"
        let layout = TopicGraphLayout(graph: graph)

        #expect(layout.cards.isEmpty)
        #expect(layout.edges.isEmpty)
        #expect(layout.size == .zero)
    }

    @Test func pendingTextDoesNotChangeTheLayout() throws {
        var graph = try busyGraph()
        let layout = TopicGraphLayout(graph: graph)
        graph.draft = "Still speaking"

        #expect(TopicGraphLayout(graph: graph) == layout)
    }

    @Test func timelineCorrectionsKeepTheRoutedOrder() throws {
        var graph = TopicGraph(meetingId: UUID())
        let first = try add(.new, at: 0, to: &graph)
        let second = try #require(try graph.apply(.init(route: .new, points: [
            .init(track: 1, start: 0, end: 1, text: "System audio"),
        ])))

        try graph.reconcileTimeline(trackOffsets: [0: 60, 1: 0],
                                    meetingStartedAt: Date(timeIntervalSince1970: 1_000))

        #expect(TopicGraphLayout(graph: graph).cards.map(\.id) == [first, second])
    }

    @Test func repeatedAndReloadedGraphsGiveTheSameLayout() throws {
        let graph = try busyGraph()
        let layout = TopicGraphLayout(graph: graph)

        for _ in 0..<10 {
            #expect(TopicGraphLayout(graph: graph) == layout)
        }
        let restored = try JSONDecoder().decode(TopicGraph.self, from: JSONEncoder().encode(graph))
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
    }

    /// A meeting with side topics, merges and returns, as in the review renders.
    private func busyGraph() throws -> TopicGraph {
        var graph = TopicGraph(meetingId: UUID())
        var time = 0.0
        func next() -> Double { time += 10; return time }
        let a = try add(.new, at: next(), to: &graph)
        let b = try add(.new, at: next(), to: &graph)
        try add(.side(b), at: next(), to: &graph)
        try add(.merge(b), at: next(), to: &graph)
        let c = try add(.new, at: next(), to: &graph)
        try add(.returnTo(a), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        let d = try add(.new, at: next(), to: &graph)
        try add(.side(d), at: next(), to: &graph)
        try add(.returnTo(b), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        let e = try add(.new, at: next(), to: &graph)
        try add(.side(e), at: next(), to: &graph)
        try add(.new, at: next(), to: &graph)
        try add(.returnTo(c), at: next(), to: &graph)
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
