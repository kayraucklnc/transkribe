import Foundation

/// Which backend runs a model.
public enum AIProviderKind: String, Codable, Sendable, CaseIterable {
    case appleIntelligence
    case claudeCode
    case anthropicAPI
}

/// A model offered by a provider. `id` is what the provider sends over the wire.
public struct AIModel: Hashable, Codable, Sendable, Identifiable {
    public var provider: AIProviderKind
    public var id: String
    public var displayName: String

    public init(provider: AIProviderKind, id: String, displayName: String) {
        self.provider = provider
        self.id = id
        self.displayName = displayName
    }
}

/// One turn of a conversation with a model.
public struct AIMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public enum AIAvailability: Equatable, Sendable {
    case available
    /// `reason` is user-facing: it says what to do to make the provider work.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}

/// Errors from providers and orchestration. `message` is user-facing.
public struct AIError: LocalizedError, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    var models: [AIModel] { get }
    /// Rough number of characters of transcript this model can take in one request (used to decide map-reduce).
    func contextCharacterBudget(for model: AIModel) -> Int
    func availability() async -> AIAvailability
    /// Streams the reply as text deltas. Stopping iteration cancels the request.
    func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error>
}

/// A generated summary of a transcript.
public struct AISummary: Codable, Hashable, Sendable {
    public var markdown: String
    public var modelName: String
    public var createdAt: Date

    public init(markdown: String, modelName: String, createdAt: Date = Date()) {
        self.markdown = markdown
        self.modelName = modelName
        self.createdAt = createdAt
    }
}

/// A Q&A conversation about a transcript.
public struct AIChat: Codable, Hashable, Sendable {
    public var messages: [AIMessage]
    public var modelName: String?

    public init(messages: [AIMessage] = [], modelName: String? = nil) {
        self.messages = messages
        self.modelName = modelName
    }
}
