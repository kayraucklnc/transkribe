import Foundation

/// Coordinates start at the top left of the canvas.
public struct TopicGraphLayout: Equatable, Sendable {
    public static let cardSize = CGSize(width: 240, height: 140)
    public static let columnGap: CGFloat = 48
    public static let rowGap: CGFloat = 64
    public static let padding: CGFloat = 32

    public struct Card: Equatable, Identifiable, Sendable {
        public let id: String
        public let frame: CGRect
        public let row: Int
    }

    public struct Edge: Equatable, Identifiable, Sendable {
        public let id: String
        public let from: String
        public let to: String
        public let type: TopicEdgeType
        /// The vertices follow the edge from the source card to the destination card.
        public let waypoints: [CGPoint]
    }

    public struct DraftCard: Equatable, Sendable {
        public let topicId: String?
        public let frame: CGRect
        public let row: Int
    }

    public let cards: [Card]
    public let edges: [Edge]
    public let draftCard: DraftCard?
    public let size: CGSize

    public init(graph: TopicGraph) {
        let ordered = graph.topics.enumerated().sorted {
            if $0.element.firstSec != $1.element.firstSec {
                return $0.element.firstSec < $1.element.firstSec
            }
            return $0.offset < $1.offset
        }.map(\.element)
        let columns = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        var byId: [String: Card] = [:]
        var nextRow = 1
        for topic in graph.topics {
            let parent = topic.parentId.flatMap { byId[$0] }
            let row = parent == nil ? 0 : nextRow
            if parent != nil { nextRow += 1 }
            let x = Self.padding + CGFloat(columns[topic.id] ?? 0) * (Self.cardSize.width + Self.columnGap)
            let frame = CGRect(x: max(x, parent.map { $0.frame.maxX + Self.columnGap } ?? x),
                               y: Self.padding + CGFloat(row) * (Self.cardSize.height + Self.rowGap),
                               width: Self.cardSize.width, height: Self.cardSize.height)
            byId[topic.id] = Card(id: topic.id, frame: frame, row: row)
        }
        cards = ordered.compactMap { byId[$0.id] }
        edges = graph.edges.compactMap { edge in
            guard let source = byId[edge.from], let target = byId[edge.to] else { return nil }
            return Edge(id: edge.id, from: edge.from, to: edge.to, type: edge.type,
                        waypoints: Self.path(from: source.frame, to: target.frame, type: edge.type))
        }
        if graph.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftCard = nil
        } else {
            let current = graph.currentTopicId.flatMap { byId[$0] }
            let row = current?.row ?? 0
            let lastX = cards.filter { $0.row == row }.map(\.frame.maxX).max()
            let frame = CGRect(x: lastX.map { $0 + Self.columnGap } ?? Self.padding,
                               y: Self.padding + CGFloat(row) * (Self.cardSize.height + Self.rowGap),
                               width: Self.cardSize.width, height: Self.cardSize.height)
            draftCard = DraftCard(topicId: current?.id, frame: frame, row: row)
        }
        let frames = cards.map(\.frame) + (draftCard.map { [$0.frame] } ?? [])
        let pathPoints = edges.flatMap(\.waypoints)
        size = frames.isEmpty ? .zero : CGSize(
            width: max(frames.map(\.maxX).max() ?? 0, pathPoints.map(\.x).max() ?? 0) + Self.padding,
            height: max(frames.map(\.maxY).max() ?? 0, pathPoints.map(\.y).max() ?? 0) + Self.padding)
    }

    private static func path(from source: CGRect, to target: CGRect, type: TopicEdgeType) -> [CGPoint] {
        let start = CGPoint(x: source.maxX, y: source.midY)
        let end = CGPoint(x: target.minX, y: target.midY)
        if type == .return || type == .merge || target.minX <= source.minX {
            let sourceLane = source.maxX + columnGap / 2
            let targetLane = target.minX - columnGap / 2
            let top = padding / 2
            return [start, CGPoint(x: sourceLane, y: start.y), CGPoint(x: sourceLane, y: top),
                    CGPoint(x: targetLane, y: top), CGPoint(x: targetLane, y: end.y), end]
        }
        if type == .branch || source.midY != target.midY || target.minX - source.maxX > columnGap {
            let start = CGPoint(x: source.midX, y: source.maxY)
            let laneY = source.maxY + rowGap / 2
            let laneX = target.minX - columnGap / 2
            return [start, CGPoint(x: start.x, y: laneY), CGPoint(x: laneX, y: laneY),
                    CGPoint(x: laneX, y: end.y), end]
        }
        return [start, end]
    }
}
