import Foundation

public enum TopicGraphInteraction {
    public enum Target: Equatable, Hashable, Sendable {
        case topic(String)
        case point(String)
    }

    public struct Region: Equatable, Sendable {
        public let target: Target
        public let frame: CGRect

        public init(target: Target, frame: CGRect) {
            self.target = target
            self.frame = frame
        }
    }

    public struct Touches: Equatable, Sendable {
        public let topicIds: Set<String>
        public let edgeIds: Set<String>
    }

    /// Regions use layout coordinates. The last region has priority when regions overlap.
    public static func hitTest(at location: CGPoint, regions: [Region]) -> Target? {
        guard location.x.isFinite, location.y.isFinite else { return nil }
        return regions.last { $0.frame.contains(location) }?.target
    }

    public static func regions(in layout: TopicGraphLayout) -> [Region] {
        layout.cards.map { Region(target: .topic($0.id), frame: $0.frame) }
    }

    /// Includes the topic, its direct neighbours, and its incoming and outgoing edges.
    public static func touches(topicId: String, in graph: TopicGraph) -> Touches {
        guard graph.topics.contains(where: { $0.id == topicId }) else {
            return Touches(topicIds: [], edgeIds: [])
        }
        let edges = graph.edges.filter { $0.from == topicId || $0.to == topicId }
        return Touches(topicIds: Set([topicId] + edges.flatMap { [$0.from, $0.to] }),
                       edgeIds: Set(edges.map(\.id)))
    }

    public static func jumpTime(to target: Target, in graph: TopicGraph) -> TimeInterval? {
        switch target {
        case .topic(let id):
            return graph.topics.first { $0.id == id }?.firstSec
        case .point(let id):
            return graph.points.first { $0.id == id }.map { graph.meetingTime(for: $0) }
        }
    }
}
