import Foundation

public enum TopicGraphInteraction {
    public enum Target: Equatable, Hashable, Sendable {
        case topic(String)
        case point(String)
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
