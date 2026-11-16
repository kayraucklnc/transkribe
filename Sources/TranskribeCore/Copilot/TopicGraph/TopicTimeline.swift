import Foundation

/// The meeting as a sequence diagram turned on its side: one row per topic, time running left to right.
///
/// - Rows follow the topic outline: main topics in the order they came up, each side topic directly
///   under the topic it branched from.
/// - A visit is a stretch of time spent on one topic. The conversation is a single path through the
///   visits, so switching topic steps from one row to another at that moment.
/// - Going back to a topic adds another visit on its existing row: the path steps back up to a row
///   that is already there, which reads as going back without any extra symbol.
public struct TopicTimeline: Equatable, Sendable {
    /// Shorter meetings are drawn on a scale of at least this long, so early visits do not fill the width.
    public static let minimumScale: TimeInterval = 60

    public struct Row: Equatable, Identifiable, Sendable {
        /// The topic id.
        public let id: String
        /// 0 for main topics, 1 for a side topic, 2 for a side topic of a side topic.
        public let depth: Int
        /// The topic this side topic branched from.
        public let parentId: String?
        /// Time spent on the topic across all its visits.
        public let totalSec: TimeInterval
        public let visitCount: Int
        /// A side topic that merged back into its parent.
        public let isResolved: Bool
    }

    public struct Visit: Equatable, Identifiable, Sendable {
        /// The graph edge that started the visit, or the topic id for the first visit.
        public let id: String
        public let topicId: String
        public let row: Int
        public let start: TimeInterval
        public let end: TimeInterval
    }

    public let rows: [Row]
    /// In conversation order: each visit starts where the previous one ends.
    public let visits: [Visit]
    /// Meeting time where the timeline ends: the latest committed speech.
    public let end: TimeInterval
    public let currentTopicId: String?

    public init(graph: TopicGraph) {
        let topics = graph.topics
        guard let first = topics.first else {
            rows = []
            visits = []
            end = 0
            currentTopicId = nil
            return
        }

        // Path through the meeting: the first topic, then one step per edge, never going back in time.
        var steps: [(id: String, topicId: String, start: TimeInterval)] = [(first.id, first.id, first.firstSec)]
        let known = Set(topics.map(\.id))
        for edge in graph.edges where known.contains(edge.to) {
            steps.append((edge.id, edge.to, max(edge.atSec, steps[steps.count - 1].start)))
        }
        let end = max(topics.map(\.lastSec).max() ?? 0, steps[steps.count - 1].start)

        let order = Self.outline(topics)
        let rowIndex = Dictionary(order.enumerated().map { ($0.element.topic.id, $0.offset) },
                                  uniquingKeysWith: { first, _ in first })
        let visits = steps.enumerated().compactMap { index, step -> Visit? in
            guard let row = rowIndex[step.topicId] else { return nil }
            let next = index + 1 < steps.count ? steps[index + 1].start : end
            return Visit(id: step.id, topicId: step.topicId, row: row, start: step.start, end: next)
        }
        let byTopic = Dictionary(grouping: visits, by: \.topicId)
        rows = order.map { item in
            let topicVisits = byTopic[item.topic.id] ?? []
            return Row(id: item.topic.id, depth: item.depth, parentId: item.topic.parentId,
                       totalSec: topicVisits.reduce(0) { $0 + $1.end - $1.start }, visitCount: topicVisits.count,
                       isResolved: item.topic.parentId != nil && item.topic.status == .resolved)
        }
        self.visits = visits
        self.end = end
        currentTopicId = graph.currentTopicId
    }

    /// Main topics in order, each followed by its side topics (depth first).
    static func outline(_ topics: [TopicGraphTopic]) -> [(topic: TopicGraphTopic, depth: Int)] {
        let known = Set(topics.map(\.id))
        let children = Dictionary(grouping: topics) { topic in topic.parentId.flatMap { known.contains($0) ? $0 : nil } }
        var result: [(topic: TopicGraphTopic, depth: Int)] = []
        var visited: Set<String> = []
        var stack: [(topic: TopicGraphTopic, depth: Int)] = (children[nil] ?? []).reversed().map { ($0, 0) }
        while let item = stack.popLast() {
            guard visited.insert(item.topic.id).inserted else { continue }
            result.append(item)
            stack.append(contentsOf: (children[item.topic.id] ?? []).reversed().map { ($0, item.depth + 1) })
        }
        return result
    }

    /// The stretch of the meeting to draw. With a span, the window slides with the conversation and
    /// shows only the last `span` seconds once the meeting is longer than that; without one it shows
    /// the whole meeting. Short meetings use at least `minimumScale`, so early visits do not fill the width.
    public func window(span: TimeInterval?) -> ClosedRange<TimeInterval> {
        guard let span, span > 0, end > span else { return 0...max(end, Self.minimumScale) }
        return (end - span)...end
    }

    /// Topics the conversation is about now: those discussed inside `window`, the current topic, and the
    /// topics they branched from. Everything else is history. A topic comes back as soon as it is discussed again.
    public func focusedTopicIds(in window: ClosedRange<TimeInterval>) -> Set<String> {
        guard window.lowerBound > 0 else { return Set(rows.map(\.id)) }
        let focused = Set(visits.filter { $0.end > window.lowerBound }.map(\.topicId) + [currentTopicId].compactMap { $0 })
        let parents = Dictionary(rows.map { ($0.id, $0.parentId) }, uniquingKeysWith: { first, _ in first })
        var withParents = focused
        for id in focused {
            // Stops at a parent that is already in, since its own parents are then in too.
            var parent = parents[id] ?? nil
            while let next = parent, withParents.insert(next).inserted {
                parent = parents[next] ?? nil
            }
        }
        return withParents
    }

    /// Horizontal position of a meeting time on a track `width` wide showing `window`.
    public func x(for time: TimeInterval, in window: ClosedRange<TimeInterval>, width: CGFloat) -> CGFloat {
        let length = max(window.upperBound - window.lowerBound, 1)
        return CGFloat((time - window.lowerBound) / length) * width
    }

    /// Ruler marks at a round interval inside `window`, at least `spacing` apart on a track `width` wide.
    public func ticks(in window: ClosedRange<TimeInterval>, width: CGFloat, spacing: CGFloat = 72) -> [TimeInterval] {
        let length = max(window.upperBound - window.lowerBound, 1)
        guard width > 0 else { return [window.lowerBound] }
        let steps: [TimeInterval] = [15, 30, 60, 120, 300, 600, 900, 1_800, 3_600, 7_200]
        let step = steps.first { CGFloat($0 / length) * width >= spacing } ?? steps[steps.count - 1]
        let first = (window.lowerBound / step).rounded(.up) * step
        return stride(from: first, through: window.upperBound, by: step).map { $0 }
    }
}
