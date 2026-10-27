import Foundation

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

    public let cards: [Card]
    public let size: CGSize

    public init(graph: TopicGraph) {
        let ordered = graph.topics.enumerated().sorted {
            if $0.element.firstSec != $1.element.firstSec {
                return $0.element.firstSec < $1.element.firstSec
            }
            return $0.offset < $1.offset
        }
        let columns = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.element.id, $0.offset) })
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
        cards = ordered.compactMap { byId[$0.element.id] }
        size = cards.isEmpty ? .zero : CGSize(
            width: (cards.map(\.frame.maxX).max() ?? 0) + Self.padding,
            height: (cards.map(\.frame.maxY).max() ?? 0) + Self.padding)
    }
}
