import Foundation

public struct IntentLagRecord: Codable, Equatable, Sendable {
    public let meetingID: UUID
    public let intentID: String
    public let from: TimeInterval
    public let to: TimeInterval
    public let speechEndedAt: Date
    public let committedAt: Date
    public let verdictAt: Date
    public let actionSentAt: Date

    public var transcriptionLag: TimeInterval { committedAt.timeIntervalSince(speechEndedAt) }
    public var decisionLag: TimeInterval { verdictAt.timeIntervalSince(committedAt) }
    public var actionLag: TimeInterval { actionSentAt.timeIntervalSince(verdictAt) }
    public var totalLag: TimeInterval { actionSentAt.timeIntervalSince(speechEndedAt) }

    public init(meetingID: UUID, intentID: String, from: TimeInterval, to: TimeInterval,
                meetingStartedAt: Date, committedAt: Date, verdictAt: Date, actionSentAt: Date) {
        self.meetingID = meetingID
        self.intentID = intentID
        self.from = from
        self.to = to
        self.speechEndedAt = meetingStartedAt.addingTimeInterval(to)
        self.committedAt = committedAt
        self.verdictAt = verdictAt
        self.actionSentAt = actionSentAt
    }
}
