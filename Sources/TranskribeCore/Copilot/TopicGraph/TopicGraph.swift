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
}
