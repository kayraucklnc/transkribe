import Foundation

public enum AnswerStoreError: Error, Equatable, LocalizedError {
    case unknownConversation
    case unknownAnswer
    case tooLarge
    case conversationExpired
    case alreadyFinal
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .unknownConversation: return "The conversation ID is unknown."
        case .unknownAnswer: return "The answer ID is unknown."
        case .tooLarge: return "The answer exceeds 32 KB of UTF-8 text."
        case .rateLimited: return "The answer permits at most 30 updates per minute. Try again after the limit expires."
        case .alreadyFinal: return "The answer is final. Later updates are not permitted."
        case .conversationExpired: return "The conversation must be live or must have ended less than 24 hours ago."
        }
    }
}

public struct AgentAnswer: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let conversationId: UUID
    public var markdown: String
    public var isFinal: Bool
    public let createdAt: Date
    public var updatedAt: Date
}

/// Stores agent answers in memory. All answer access uses the same lock.
/// Snapshot and clock closures run before the lock. They must support concurrent calls.
public final class AnswerStore: @unchecked Sendable {
    private let lock = NSLock()
    private let snapshots: () -> [MCPConversationSnapshot]
    private let now: () -> Date
    private var stored: [UUID: AgentAnswer] = [:]
    private var updateTimes: [UUID: [Date]] = [:]

    public init(snapshots: @escaping () -> [MCPConversationSnapshot], now: @escaping () -> Date = Date.init) {
        self.snapshots = snapshots
        self.now = now
    }

    public func post(conversationId: UUID, markdown: String) throws -> AgentAnswer {
        let conversations = snapshots()
        let time = now()
        lock.lock()
        defer { lock.unlock() }
        try validate(conversationId: conversationId, markdown: markdown, snapshots: conversations, at: time)
        let answer = AgentAnswer(id: UUID(), conversationId: conversationId, markdown: markdown,
                                 isFinal: false, createdAt: time, updatedAt: time)
        stored[answer.id] = answer
        return answer
    }

    public func update(answerId: UUID, markdown: String, final: Bool) throws -> AgentAnswer {
        let conversations = snapshots()
        let time = now()
        lock.lock()
        defer { lock.unlock() }
        guard var answer = stored[answerId] else { throw AnswerStoreError.unknownAnswer }
        guard !answer.isFinal else { throw AnswerStoreError.alreadyFinal }
        try validate(conversationId: answer.conversationId, markdown: markdown, snapshots: conversations, at: time)
        let recent = (updateTimes[answerId] ?? []).filter { time.timeIntervalSince($0) < 60 }
        guard recent.count < 30 else { throw AnswerStoreError.rateLimited }
        updateTimes[answerId] = recent + [time]
        answer.markdown = markdown
        answer.isFinal = final
        answer.updatedAt = time
        stored[answerId] = answer
        return answer
    }

    public func answers(for conversationId: UUID) -> [AgentAnswer] {
        lock.lock()
        defer { lock.unlock() }
        return stored.values.filter { $0.conversationId == conversationId }.sorted { $0.createdAt < $1.createdAt }
    }

    private func validate(conversationId: UUID, markdown: String, snapshots: [MCPConversationSnapshot], at time: Date) throws {
        guard let conversation = snapshots.first(where: { $0.transcript.id == conversationId }) else {
            throw AnswerStoreError.unknownConversation
        }
        if !conversation.isLive {
            guard let endedAt = conversation.endedAt,
                  time.timeIntervalSince(endedAt) >= 0,
                  time.timeIntervalSince(endedAt) < 86_400 else {
                throw AnswerStoreError.conversationExpired
            }
        }
        guard markdown.utf8.count <= 32_768 else { throw AnswerStoreError.tooLarge }
    }
}
