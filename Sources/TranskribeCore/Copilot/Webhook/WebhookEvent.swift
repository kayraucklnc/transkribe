import Foundation

public struct WebhookEvent: Encodable, Equatable, Sendable {
    public enum EventType: String, Encodable, Sendable {
        case meetingStarted = "meeting.started"
        case meetingEnded = "meeting.ended"
        case intent
    }

    public struct Intent: Encodable, Equatable, Sendable {
        public let id: String
        public let instruction: String
        public let request: String
        public let context: String

        public init(id: String, instruction: String, request: String, context: String) {
            self.id = id
            self.instruction = instruction
            self.request = request
            self.context = context
        }
    }

    public let version = 1
    public let type: EventType
    public let eventId: UUID
    public let conversationId: UUID
    public let title: String
    public let startedAt: Date
    public let intent: Intent?

    public init(type: EventType, eventId: UUID = UUID(), conversationId: UUID, title: String, startedAt: Date,
                intent: Intent? = nil) {
        self.type = type
        self.eventId = eventId
        self.conversationId = conversationId
        self.title = title
        self.startedAt = startedAt
        self.intent = intent
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
