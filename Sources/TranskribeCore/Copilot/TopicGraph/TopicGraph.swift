import Foundation

private struct TopicPointKey: Hashable {
    let track: Int
    let start: TimeInterval
    let end: TimeInterval
}

public struct TopicGraph: Codable, Equatable, Sendable {
    public static let maxLabelLength = 80
    public static let maxSummaryLength = 240

    public private(set) var version = 1
    public let meetingId: UUID
    public private(set) var untilSec: TimeInterval = 0
    public private(set) var currentTopicId: String?
    public private(set) var topics: [TopicGraphTopic] = []
    public private(set) var points: [TopicGraphPoint] = []
    public private(set) var edges: [TopicGraphEdge] = []
    /// Pending text for the current topic. Codable excludes this value.
    public var draft = ""

    private enum CodingKeys: String, CodingKey {
        case version, meetingId, untilSec, currentTopicId, topics, points, edges
    }

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    /// Returns the destination topic, or nil when the batch contains no new points.
    @discardableResult
    public mutating func apply(_ proposal: TopicGraphProposal) throws -> String? {
        guard proposal.points.allSatisfy({
            $0.track >= 0 && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start
        }) else { throw TopicGraphError.invalidPoint }
        if let confidence = proposal.confidence, !confidence.isFinite || !(0...1).contains(confidence) {
            throw TopicGraphError.invalidConfidence
        }
        var seen = Set(points.map { TopicPointKey(track: $0.track, start: $0.start, end: $0.end) })
        let incoming = proposal.points.filter {
            seen.insert(TopicPointKey(track: $0.track, start: $0.start, end: $0.end)).inserted
        }
        guard let first = incoming.first else { return nil }
        let previous = currentTopicId
        let (index, edgeType) = try destination(for: proposal.route, first: first)
        let topicId = topics[index].id
        currentTopicId = topicId
        topics[index].status = .open
        let firstPointId = UUID().uuidString
        for (offset, point) in incoming.enumerated() {
            let id = offset == 0 ? firstPointId : UUID().uuidString
            points.append(.init(id: id, topicId: topicId, track: point.track,
                                start: point.start, end: point.end, speaker: point.speaker,
                                kind: point.kind, text: point.text))
            topics[index].firstSec = min(topics[index].firstSec, point.start)
            topics[index].lastSec = max(topics[index].lastSec, point.end)
            topics[index].totalSec += point.end - point.start
            untilSec = max(untilSec, point.end)
        }
        if let previous, let edgeType {
            let from = edgeType == .branch ? topics[index].parentId ?? previous : previous
            edges.append(.init(id: UUID().uuidString, from: from, to: topicId, type: edgeType,
                               atSec: first.start, pointId: firstPointId, confidence: proposal.confidence))
        }
        return topicId
    }

    public mutating func setName(topicId: String, label: String, summary: String) throws {
        guard let index = topics.firstIndex(where: { $0.id == topicId }) else { throw TopicGraphError.unknownTopic }
        let label = Self.singleLine(label, limit: Self.maxLabelLength)
        guard !label.isEmpty else { throw TopicGraphError.invalidName }
        topics[index].label = label
        topics[index].summary = Self.singleLine(summary, limit: Self.maxSummaryLength)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else { throw TopicGraphError.unsupportedVersion }
        meetingId = try container.decode(UUID.self, forKey: .meetingId)
        untilSec = try container.decode(TimeInterval.self, forKey: .untilSec)
        currentTopicId = try container.decodeIfPresent(String.self, forKey: .currentTopicId)
        topics = try container.decode([TopicGraphTopic].self, forKey: .topics)
        points = try container.decode([TopicGraphPoint].self, forKey: .points)
        edges = try container.decode([TopicGraphEdge].self, forKey: .edges)
        try validate()
    }

    private mutating func destination(for route: TopicRoute, first: TopicPointInput) throws -> (Int, TopicEdgeType?) {
        let current = topics.firstIndex { $0.id == currentTopicId }
        switch route {
        case .continue:
            if let current { return (current, nil) }
            return (openTopic(first: first), nil)
        case .new:
            return (openTopic(first: first), current == nil ? nil : .shift)
        case .returnTo(let id):
            guard let target = topics.firstIndex(where: { $0.id == id }) else { throw TopicGraphError.unknownTopic }
            guard let current, target < current else { throw TopicGraphError.invalidRoute }
            return (target, .return)
        case .side(let id):
            guard let parent = topics.first(where: { $0.id == id }) else { throw TopicGraphError.unknownTopic }
            guard parent.status == .open else { throw TopicGraphError.invalidRoute }
            return (openTopic(first: first, parentId: id), .branch)
        case .merge(let id):
            guard let target = topics.firstIndex(where: { $0.id == id }) else { throw TopicGraphError.unknownTopic }
            guard let current, topics[current].parentId != nil,
                  id == topics[current].parentId || target < current else { throw TopicGraphError.invalidRoute }
            topics[current].status = .resolved
            return (target, .merge)
        }
    }

    private mutating func openTopic(first: TopicPointInput, parentId: String? = nil) -> Int {
        let label = Self.singleLine(first.text, limit: Self.maxLabelLength)
        topics.append(.init(id: UUID().uuidString, label: label.isEmpty ? "Topic" : label, summary: "", status: .open,
                            parentId: parentId, firstSec: first.start, lastSec: first.end, totalSec: 0))
        return topics.count - 1
    }

    private static func singleLine(_ text: String, limit: Int) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
    }

    private func validate() throws {
        guard untilSec.isFinite, untilSec >= 0,
              Set(topics.map(\.id)).count == topics.count,
              Set(points.map(\.id)).count == points.count,
              Set(edges.map(\.id)).count == edges.count,
              topics.allSatisfy({ !$0.id.isEmpty }),
              points.allSatisfy({ !$0.id.isEmpty }),
              edges.allSatisfy({ !$0.id.isEmpty }),
              topics.isEmpty == (currentTopicId == nil) else { throw TopicGraphError.invalidGraph }
        let indices = Dictionary(uniqueKeysWithValues: topics.enumerated().map { ($0.element.id, $0.offset) })
        if let currentTopicId, indices[currentTopicId] == nil { throw TopicGraphError.invalidGraph }
        var ranges = Set<TopicPointKey>()
        for point in points {
            guard indices[point.topicId] != nil, point.track >= 0,
                  point.start.isFinite, point.end.isFinite, point.start >= 0,
                  point.end >= point.start, untilSec >= point.end,
                  ranges.insert(.init(track: point.track, start: point.start, end: point.end)).inserted
            else { throw TopicGraphError.invalidGraph }
        }
        let grouped = Dictionary(grouping: points, by: \.topicId)
        for (index, topic) in topics.enumerated() {
            if let parent = topic.parentId {
                guard let parentIndex = indices[parent], parentIndex < index else { throw TopicGraphError.invalidGraph }
            }
            guard !topic.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  topic.label.count <= Self.maxLabelLength, topic.summary.count <= Self.maxSummaryLength,
                  topic.firstSec.isFinite, topic.lastSec.isFinite, topic.totalSec.isFinite,
                  let topicPoints = grouped[topic.id],
                  topic.firstSec == topicPoints.map(\.start).min(),
                  topic.lastSec == topicPoints.map(\.end).max() else { throw TopicGraphError.invalidGraph }
            let total = topicPoints.reduce(0) { $0 + ($1.end - $1.start) }
            guard total.isFinite, abs(total - topic.totalSec) <= max(1, total) * 1e-9
            else { throw TopicGraphError.invalidGraph }
        }
        let pointsById = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        for edge in edges {
            guard let from = indices[edge.from], let to = indices[edge.to], from != to,
                  let point = pointsById[edge.pointId], point.topicId == edge.to, edge.atSec == point.start
            else { throw TopicGraphError.invalidGraph }
            if let confidence = edge.confidence, !confidence.isFinite || !(0...1).contains(confidence) {
                throw TopicGraphError.invalidGraph
            }
            switch edge.type {
            case .shift:
                guard to > from, topics[to].parentId == nil else { throw TopicGraphError.invalidGraph }
            case .return:
                guard to < from else { throw TopicGraphError.invalidGraph }
            case .branch:
                guard to > from, topics[to].parentId == edge.from else { throw TopicGraphError.invalidGraph }
            case .merge:
                guard topics[from].parentId != nil, edge.to == topics[from].parentId || to < from
                else { throw TopicGraphError.invalidGraph }
            }
        }
    }
}
