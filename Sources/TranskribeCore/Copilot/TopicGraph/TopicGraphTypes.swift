import Foundation

public enum TopicStatus: String, Codable, Sendable {
    case open, resolved, parked
}

public enum TopicPointKind: String, Codable, Sendable {
    case statement, question, decision, action, objection
}

public enum TopicEdgeType: String, Codable, Sendable {
    case shift, `return`, branch, merge
}

public enum TopicRoute: Equatable, Sendable {
    case `continue`
    case new
    case returnTo(String)
    case side(String)
    case merge(String)
}

public enum TopicGraphError: Error, Equatable, LocalizedError {
    case unknownTopic
    case invalidRoute
    case invalidPoint
    case invalidConfidence
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .unknownTopic: return "The topic does not exist."
        case .invalidRoute: return "The route target is not valid for the current topic."
        case .invalidPoint: return "A point must have a valid track and a finite, nonnegative time range."
        case .invalidConfidence: return "The confidence must be a finite number from zero to one."
        case .invalidName: return "The topic label must contain text."
        }
    }
}

/// Times are relative to the audio track, as in RawSegment.
public struct TopicPointInput: Equatable, Sendable {
    public let track: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let speaker: Int?
    public let kind: TopicPointKind

    public init(track: Int, start: TimeInterval, end: TimeInterval, text: String,
                speaker: Int? = nil, kind: TopicPointKind = .statement) {
        self.track = track
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.kind = kind
    }
}

/// A model proposes a route and points. The graph assigns all identifiers.
public struct TopicGraphProposal: Equatable, Sendable {
    public let route: TopicRoute
    public let points: [TopicPointInput]
    public let confidence: Double?

    public init(route: TopicRoute, points: [TopicPointInput], confidence: Double? = nil) {
        self.route = route
        self.points = points
        self.confidence = confidence
    }
}

public struct TopicGraphTopic: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public internal(set) var label: String
    public internal(set) var summary: String
    public internal(set) var status: TopicStatus
    public let parentId: String?
    public internal(set) var firstSec: TimeInterval
    public internal(set) var lastSec: TimeInterval
    /// Sum of the unique points' durations, including simultaneous tracks.
    public internal(set) var totalSec: TimeInterval
}

public struct TopicGraphPoint: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let topicId: String
    public let track: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let speaker: Int?
    public let kind: TopicPointKind
    public let text: String
}

public struct TopicGraphEdge: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let from: String
    public let to: String
    public let type: TopicEdgeType
    public let atSec: TimeInterval
    public let pointId: String
    public let confidence: Double?
}
