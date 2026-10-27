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
        cards = ordered.enumerated().map { column, topic in
            Card(id: topic.element.id,
                 frame: CGRect(x: Self.padding + CGFloat(column) * (Self.cardSize.width + Self.columnGap),
                               y: Self.padding, width: Self.cardSize.width, height: Self.cardSize.height),
                 row: 0)
        }
        size = cards.last.map {
            CGSize(width: $0.frame.maxX + Self.padding, height: $0.frame.maxY + Self.padding)
        } ?? .zero
    }
}
