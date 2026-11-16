import Foundation

/// Lays the meeting out as the path the conversation took, left to right in routing order.
/// Coordinates start at the top left of the canvas.
///
/// - Each topic appears once, where it started. Main topics share row 0; a side topic sits one
///   row below its parent, and siblings share that row.
/// - Going back to an earlier topic (a return, or a merge into the parent) adds a small revisit
///   card at that moment instead of an edge that travels back across the canvas.
/// - Every link joins two neighbouring cards with one smooth curve, so links never cross cards
///   or each other, however long the meeting gets.
/// - Given a width, the path wraps onto the next line like text, so a long meeting fits the window
///   at full size. One rounded connector runs through the gap between lines.
/// - In long meetings, older topics collapse to compact cards. The current topic, its direct
///   neighbours and the most recently active topics stay full size.
public struct TopicGraphLayout: Equatable, Sendable {
    public static let cardSize = CGSize(width: 224, height: 84)
    public static let compactSize = CGSize(width: 156, height: 40)
    public static let columnGap: CGFloat = 64
    public static let rowGap: CGFloat = 48
    public static let padding: CGFloat = 24
    /// Space between wrapped lines; the connector between lines runs through its middle.
    public static let lineGap: CGFloat = 56
    static let cornerRadius: CGFloat = 16
    /// Graphs with more topics than this collapse their older topics.
    public static let collapseThreshold = 8
    /// How many of the most recently active topics stay full size in a collapsed graph.
    public static let recentTopics = 4

    public struct Card: Equatable, Identifiable, Sendable {
        /// The topic id where the topic starts; a unique id for each revisit.
        public let id: String
        public let topicId: String
        /// `.return` or `.merge` when the conversation went back to this topic here.
        public let revisit: TopicEdgeType?
        public let frame: CGRect
        public let row: Int
        /// The wrapped line the card is on.
        public let line: Int
        public let isCompact: Bool
    }

    /// A cubic Bézier curve from `start` to `end`.
    public struct Curve: Equatable, Sendable {
        public let start: CGPoint
        public let control1: CGPoint
        public let control2: CGPoint
        public let end: CGPoint

        public func point(at t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                           y: a * start.y + b * control1.y + c * control2.y + d * end.y)
        }

        public func samples(count: Int = 24) -> [CGPoint] {
            (0...count).map { point(at: CGFloat($0) / CGFloat(count)) }
        }

        /// The direction the curve arrives in, for the arrowhead.
        public var endAngle: CGFloat { atan2(end.y - control2.y, end.x - control2.x) }
    }

    /// One step of the conversation. `id` is the graph edge's id, so hover can match it.
    public struct Edge: Equatable, Identifiable, Sendable {
        public let id: String
        /// Card ids.
        public let from: String
        public let to: String
        public let type: TopicEdgeType
        /// One curve between cards on a line; several between lines.
        public let segments: [Curve]

        public var start: CGPoint { segments.first?.start ?? .zero }
        public var end: CGPoint { segments.last?.end ?? .zero }
        public var endAngle: CGFloat { segments.last?.endAngle ?? 0 }
    }

    public let cards: [Card]
    public let edges: [Edge]
    /// Where the conversation is now: the last card in the path.
    public let currentCardId: String?
    public let size: CGSize

    /// - Parameter width: The width to wrap at. Without one, the path stays on one line.
    public init(graph: TopicGraph, width: CGFloat = .infinity) {
        let topics = Dictionary(uniqueKeysWithValues: graph.topics.map { ($0.id, $0) })
        let collapsed = Self.collapsedTopicIds(in: graph)
        var rows: [String: Int] = [:]
        for topic in graph.topics {
            rows[topic.id] = topic.parentId.flatMap { rows[$0] }.map { $0 + 1 } ?? 0
        }

        // Lines first: a line's height depends on its deepest side topic.
        // A main-row card and the side topics that follow it form a group that wraps as one,
        // so a side excursion stays on the line of the card it leaves from.
        var groups: [[(step: Step, row: Int, size: CGSize, isCompact: Bool)]] = []
        for step in Self.path(through: graph) {
            guard let row = rows[step.topicId], topics[step.topicId] != nil else { continue }
            let isCompact = step.revisit != nil || collapsed.contains(step.topicId)
            let item = (step, row, isCompact ? Self.compactSize : Self.cardSize, isCompact)
            if row == 0 || groups.isEmpty { groups.append([item]) } else { groups[groups.count - 1].append(item) }
        }
        var placed: [(step: Step, row: Int, size: CGSize, x: CGFloat, line: Int, isCompact: Bool)] = []
        var x = Self.padding, line = 0
        func fits(_ extent: CGFloat) -> Bool { x == Self.padding || x + extent + Self.padding <= width }
        for group in groups {
            let extent = group.map(\.size.width).reduce(0, +) + CGFloat(group.count - 1) * Self.columnGap
            if !fits(extent) { line += 1; x = Self.padding }
            for item in group {
                // A group wider than a whole line still breaks between its cards.
                if !fits(item.size.width) { line += 1; x = Self.padding }
                placed.append((item.step, item.row, item.size, x, line, item.isCompact))
                x += item.size.width + Self.columnGap
            }
        }
        let rowStep = Self.cardSize.height + Self.rowGap
        var lineTops: [CGFloat] = []
        var top = Self.padding
        for index in 0..<(placed.last.map { $0.line + 1 } ?? 0) {
            lineTops.append(top)
            let deepest = placed.filter { $0.line == index }.map(\.row).max() ?? 0
            top += CGFloat(deepest) * rowStep + Self.cardSize.height + Self.lineGap
        }

        let cards = placed.map { item in
            // Compact cards stay centred on their row, so links along a row stay straight.
            let y = lineTops[item.line] + CGFloat(item.row) * rowStep + (Self.cardSize.height - item.size.height) / 2
            return Card(id: item.step.cardId, topicId: item.step.topicId, revisit: item.step.revisit,
                        frame: CGRect(origin: CGPoint(x: item.x, y: y), size: item.size), row: item.row,
                        line: item.line, isCompact: item.isCompact)
        }
        let byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        edges = placed.compactMap { item in
            guard let edge = item.step.edge, let from = item.step.previousCardId,
                  let source = byId[from], let target = byId[item.step.cardId] else { return nil }
            let segments = source.line == target.line
                ? [Self.curve(from: source.frame, to: target.frame)]
                : Self.wrap(from: source.frame, to: target.frame, gapY: lineTops[target.line] - Self.lineGap / 2)
            return Edge(id: edge.id, from: from, to: item.step.cardId, type: edge.type, segments: segments)
        }
        self.cards = cards
        currentCardId = cards.last?.id
        size = cards.isEmpty ? .zero : CGSize(width: (cards.map(\.frame.maxX).max() ?? 0) + Self.padding,
                                              height: (cards.map(\.frame.maxY).max() ?? 0) + Self.padding)
    }

    /// Topics shown as compact cards. Short graphs collapse nothing.
    public static func collapsedTopicIds(in graph: TopicGraph) -> Set<String> {
        guard graph.topics.count > collapseThreshold else { return [] }
        var expanded = Set(graph.topics.enumerated()
            .sorted { ($0.element.lastSec, $0.offset) > ($1.element.lastSec, $1.offset) }
            .prefix(recentTopics).map(\.element.id))
        if let current = graph.currentTopicId {
            expanded.formUnion(TopicGraphInteraction.touches(topicId: current, in: graph).topicIds)
        }
        return Set(graph.topics.map(\.id)).subtracting(expanded)
    }

    struct Step {
        let cardId: String
        let topicId: String
        let revisit: TopicEdgeType?
        let edge: TopicGraphEdge?
        let previousCardId: String?
    }

    /// The conversation in routing order: graph edges are appended as the meeting is routed.
    static func path(through graph: TopicGraph) -> [Step] {
        guard let first = graph.topics.first else { return [] }
        var steps = [Step(cardId: first.id, topicId: first.id, revisit: nil, edge: nil, previousCardId: nil)]
        var placed: Set<String> = [first.id]
        for edge in graph.edges {
            let previous = steps.last?.cardId
            if edge.type == .return || edge.type == .merge {
                steps.append(Step(cardId: "revisit-\(edge.id)", topicId: edge.to, revisit: edge.type, edge: edge,
                                  previousCardId: previous))
            } else if placed.insert(edge.to).inserted {
                steps.append(Step(cardId: edge.to, topicId: edge.to, revisit: nil, edge: edge, previousCardId: previous))
            }
        }
        // Topics that no edge reaches still get a card, without a link.
        for topic in graph.topics where placed.insert(topic.id).inserted {
            steps.append(Step(cardId: topic.id, topicId: topic.id, revisit: nil, edge: nil, previousCardId: nil))
        }
        return steps
    }

    /// Neighbouring cards on a line: straight along a row, an S-curve between rows.
    static func curve(from s: CGRect, to t: CGRect) -> Curve {
        let start = CGPoint(x: s.maxX, y: s.midY), end = CGPoint(x: t.minX, y: t.midY)
        let half = (end.x - start.x) / 2
        return Curve(start: start, control1: CGPoint(x: start.x + half, y: start.y),
                     control2: CGPoint(x: end.x - half, y: end.y), end: end)
    }

    /// From the end of one line to the start of the next: down from the card, along the gap between
    /// lines, and down into the next card. Cards own their column, so nothing sits in the way.
    static func wrap(from s: CGRect, to t: CGRect, gapY: CGFloat) -> [Curve] {
        let start = CGPoint(x: s.midX, y: s.maxY), end = CGPoint(x: t.midX, y: t.minY)
        let radius = min(cornerRadius, abs(start.x - end.x) / 2, (gapY - start.y) / 2, (end.y - gapY) / 2)
        guard radius > 1 else { return [line(from: start, to: end)] }
        let direction: CGFloat = end.x < start.x ? -1 : 1
        let down = CGPoint(x: start.x, y: gapY - radius)
        let turned = CGPoint(x: start.x + direction * radius, y: gapY)
        let across = CGPoint(x: end.x - direction * radius, y: gapY)
        let into = CGPoint(x: end.x, y: gapY + radius)
        return [line(from: start, to: down), corner(from: down, at: CGPoint(x: start.x, y: gapY), to: turned),
                line(from: turned, to: across), corner(from: across, at: CGPoint(x: end.x, y: gapY), to: into),
                line(from: into, to: end)]
    }

    static func line(from a: CGPoint, to b: CGPoint) -> Curve {
        Curve(start: a, control1: CGPoint(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3),
              control2: CGPoint(x: a.x + (b.x - a.x) * 2 / 3, y: a.y + (b.y - a.y) * 2 / 3), end: b)
    }

    /// A rounded corner: 0.55 of the way to the corner approximates a quarter circle.
    static func corner(from a: CGPoint, at c: CGPoint, to b: CGPoint) -> Curve {
        Curve(start: a, control1: CGPoint(x: a.x + (c.x - a.x) * 0.55, y: a.y + (c.y - a.y) * 0.55),
              control2: CGPoint(x: b.x + (c.x - b.x) * 0.55, y: b.y + (c.y - b.y) * 0.55), end: b)
    }
}
