import Foundation

/// The meeting's structure as a map: which topics came up and what branched from what. Time and
/// returns live in `TopicTimeline`; here each topic appears exactly once.
///
/// - Main topics run left to right in the order they came up, joined by one spine.
/// - Each main topic carries its side topics beneath it as a small tree, like an org chart.
/// - Main topics and their trees wrap onto the next line like text, so the map fits the width.
/// - Given a focus, topics the conversation has moved on from become history: their side topics
///   are hidden and the main topic shrinks to a quiet compact card, until it is discussed again.
public struct TopicMapLayout: Equatable, Sendable {
    public static let mainSize = CGSize(width: 208, height: 64)
    public static let sideSize = CGSize(width: 184, height: 56)
    public static let dormantSize = CGSize(width: 168, height: 40)
    public static let siblingGap: CGFloat = 20
    public static let levelGap: CGFloat = 40
    public static let blockGap: CGFloat = 56
    public static let lineGap: CGFloat = 56
    public static let padding: CGFloat = 24
    static let cornerRadius: CGFloat = 12

    public struct Node: Equatable, Identifiable, Sendable {
        /// The topic id.
        public let id: String
        public let frame: CGRect
        public let depth: Int
        public let line: Int
        /// A main topic the conversation has moved on from, drawn compact.
        public let isDormant: Bool
    }

    public enum LinkKind: Equatable, Sendable {
        /// From one main topic to the next.
        case spine
        /// From a topic to one of its side topics.
        case branch
    }

    public struct Link: Equatable, Identifiable, Sendable {
        public let id: String
        public let from: String
        public let to: String
        public let kind: LinkKind
        public let segments: [Curve]
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

        public func samples(count: Int = 16) -> [CGPoint] {
            (0...count).map { point(at: CGFloat($0) / CGFloat(count)) }
        }
    }

    public let nodes: [Node]
    public let links: [Link]
    public let size: CGSize

    /// - Parameters:
    ///   - width: The width to wrap at. Without one, all main topics stay on one line.
    ///   - focus: Topics in focus (see `TopicTimeline.focusedTopicIds`). Without one, everything is shown in full.
    public init(graph: TopicGraph, width: CGFloat = .infinity, focus: Set<String>? = nil) {
        let isDormant = { (id: String) in focus.map { !$0.contains(id) } ?? false }
        let outline = TopicTimeline.outline(graph.topics).filter { $0.depth == 0 || !isDormant($0.topic.id) }
        func nodeSize(_ id: String, depth: Int) -> CGSize { isDormant(id) ? Self.dormantSize : Self.size(depth: depth) }
        let children = Dictionary(grouping: outline.filter { $0.depth > 0 }) { $0.topic.parentId ?? "" }
        let mains = outline.filter { $0.depth == 0 }.map(\.topic)
        var widths: [String: CGFloat] = [:]
        var heights: [String: CGFloat] = [:]
        // Children come after their parent in the outline, so walk it backwards to size subtrees.
        for item in outline.reversed() {
            let size = nodeSize(item.topic.id, depth: item.depth)
            let kids = (children[item.topic.id] ?? []).map(\.topic.id)
            let kidsWidth = kids.map { widths[$0] ?? 0 }.reduce(0, +) + CGFloat(max(kids.count - 1, 0)) * Self.siblingGap
            widths[item.topic.id] = max(size.width, kidsWidth)
            // Every main topic takes a full row, so compact ones line up with the rest.
            let height = item.depth == 0 ? max(size.height, Self.mainSize.height) : size.height
            heights[item.topic.id] = height + (kids.isEmpty ? 0 : Self.levelGap + (kids.compactMap { heights[$0] }.max() ?? 0))
        }

        // Flow the main topics' trees into lines.
        var placements: [(id: String, x: CGFloat, line: Int)] = []
        var x = Self.padding, line = 0
        for main in mains {
            let blockWidth = widths[main.id] ?? nodeSize(main.id, depth: 0).width
            if x > Self.padding, x + blockWidth + Self.padding > width {
                line += 1
                x = Self.padding
            }
            placements.append((main.id, x, line))
            x += blockWidth + Self.blockGap
        }
        var lineTops: [CGFloat] = []
        var top = Self.padding
        for index in 0..<(placements.last.map { $0.line + 1 } ?? 0) {
            lineTops.append(top)
            top += (placements.filter { $0.line == index }.compactMap { heights[$0.id] }.max() ?? 0) + Self.lineGap
        }

        var nodes: [Node] = []
        var links: [Link] = []
        func place(_ id: String, depth: Int, left: CGFloat, top: CGFloat, line: Int) {
            let cardSize = nodeSize(id, depth: depth)
            let span = widths[id] ?? cardSize.width
            // Main topics on a line share a centre line, so the spine between them stays straight.
            let lift = depth == 0 ? (Self.mainSize.height - cardSize.height) / 2 : 0
            let frame = CGRect(x: left + (span - cardSize.width) / 2, y: top + lift,
                               width: cardSize.width, height: cardSize.height)
            nodes.append(Node(id: id, frame: frame, depth: depth, line: line, isDormant: isDormant(id)))
            let kids = (children[id] ?? []).map(\.topic.id)
            let kidsWidth = kids.map { widths[$0] ?? 0 }.reduce(0, +) + CGFloat(max(kids.count - 1, 0)) * Self.siblingGap
            var childLeft = left + (span - kidsWidth) / 2
            let childTop = frame.maxY + Self.levelGap
            for kid in kids {
                let kidSpan = widths[kid] ?? 0
                let kidCentre = childLeft + kidSpan / 2
                let bus = frame.maxY + Self.levelGap / 2
                links.append(Link(id: "branch-\(kid)", from: id, to: kid, kind: .branch, segments: Self.rounded([
                    CGPoint(x: frame.midX, y: frame.maxY), CGPoint(x: frame.midX, y: bus),
                    CGPoint(x: kidCentre, y: bus), CGPoint(x: kidCentre, y: childTop),
                ])))
                place(kid, depth: depth + 1, left: childLeft, top: childTop, line: line)
                childLeft += kidSpan + Self.siblingGap
            }
        }
        for placement in placements {
            place(placement.id, depth: 0, left: placement.x, top: lineTops[placement.line], line: placement.line)
        }

        let frames = Dictionary(nodes.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        for (previous, next) in zip(placements, placements.dropFirst()) {
            guard let a = frames[previous.id], let b = frames[next.id] else { continue }
            let points: [CGPoint]
            if previous.line == next.line {
                points = [CGPoint(x: a.maxX, y: a.midY), CGPoint(x: b.minX, y: b.midY)]
            } else {
                // Out of the last topic on a line, through the gap below it, into the first topic of the next.
                let gapY = lineTops[next.line] - Self.lineGap / 2
                // Run down past the whole tree of the last topic, not just its card.
                let blockRight = previous.x + (widths[previous.id] ?? a.width)
                let right = blockRight + Self.blockGap / 3, left = b.minX - Self.padding / 2
                points = [CGPoint(x: a.maxX, y: a.midY), CGPoint(x: right, y: a.midY), CGPoint(x: right, y: gapY),
                          CGPoint(x: left, y: gapY), CGPoint(x: left, y: b.midY), CGPoint(x: b.minX, y: b.midY)]
            }
            links.append(Link(id: "spine-\(next.id)", from: previous.id, to: next.id, kind: .spine,
                              segments: Self.rounded(points)))
        }

        self.nodes = nodes
        self.links = links
        let linkRight = links.flatMap { $0.segments.map(\.end.x) }.max() ?? 0
        size = nodes.isEmpty ? .zero : CGSize(width: max(nodes.map(\.frame.maxX).max() ?? 0, linkRight) + Self.padding,
                                              height: (nodes.map(\.frame.maxY).max() ?? 0) + Self.padding)
    }

    static func size(depth: Int) -> CGSize { depth == 0 ? mainSize : sideSize }

    /// A polyline with rounded corners, as curves. Straight runs are curves with their controls on the line.
    static func rounded(_ points: [CGPoint]) -> [Curve] {
        guard points.count > 1 else { return [] }
        var curves: [Curve] = []
        var cursor = points[0]
        for index in 1..<(points.count - 1) {
            let corner = points[index], before = points[index - 1], after = points[index + 1]
            let radius = min(cornerRadius, distance(before, corner) / 2, distance(corner, after) / 2)
            let entry = towards(corner, from: before, by: radius)
            let exit = towards(corner, from: after, by: radius)
            if distance(cursor, entry) > 0.01 { curves.append(line(from: cursor, to: entry)) }
            if radius > 0.01 {
                curves.append(Curve(start: entry, control1: mix(entry, corner, 0.55), control2: mix(exit, corner, 0.55), end: exit))
            }
            cursor = exit
        }
        if let last = points.last, distance(cursor, last) > 0.01 { curves.append(line(from: cursor, to: last)) }
        return curves
    }

    private static func line(from a: CGPoint, to b: CGPoint) -> Curve {
        Curve(start: a, control1: mix(a, b, 1.0 / 3), control2: mix(a, b, 2.0 / 3), end: b)
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    /// The point `distance` before `corner` on the way from `start`.
    private static func towards(_ corner: CGPoint, from start: CGPoint, by distance: CGFloat) -> CGPoint {
        let length = Self.distance(start, corner)
        guard length > 0 else { return corner }
        return mix(corner, start, distance / length)
    }
}
