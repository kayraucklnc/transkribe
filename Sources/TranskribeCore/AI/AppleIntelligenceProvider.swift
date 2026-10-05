import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device language model (macOS 26+). Private and free, but with a small context
/// window (~4096 tokens for instructions, prompt and reply together).
public struct AppleIntelligenceProvider: AIProvider {
    public static let model = AIModel(provider: .appleIntelligence, id: "apple-on-device", displayName: "Apple Intelligence (on-device)")

    public let kind = AIProviderKind.appleIntelligence
    public var models: [AIModel] { [Self.model] }

    public init() {}

    public func contextCharacterBudget(for model: AIModel) -> Int {
        6_000
    }

    public func availability() async -> AIAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return Self.availability(of: SystemLanguageModel.default)
        }
        #endif
        return .unavailable(reason: "Apple Intelligence needs macOS 26 or later.")
    }

    public func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let prompt = ConversationRenderer.prompt(from: messages)
            return AIStreaming.run { yield in
                try await Self.respond(system: system, prompt: prompt, yield: yield)
            }
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: AIError("Apple Intelligence needs macOS 26 or later.")) }
    }

    /// The part of `snapshot` that is new compared to what was already yielded.
    static func delta(from previous: String, to snapshot: String) -> String {
        if snapshot.hasPrefix(previous) { return String(snapshot.dropFirst(previous.count)) }
        // The model rewrote earlier text; yield what follows the shared prefix.
        let shared = zip(previous, snapshot).prefix { $0 == $1 }.count
        return String(snapshot.dropFirst(shared))
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func availability(of model: SystemLanguageModel) -> AIAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This Mac doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Apple Intelligence is still downloading its model. Try again in a few minutes.")
        case .unavailable:
            return .unavailable(reason: "Apple Intelligence isn't available right now.")
        }
    }

    @available(macOS 26, *)
    private static func respond(system: String, prompt: String, yield: @Sendable (String) -> Void) async throws {
        let session = LanguageModelSession(instructions: system)
        var previous = ""
        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                let text = snapshot.content
                let delta = delta(from: previous, to: text)
                if !delta.isEmpty { yield(delta) }
                previous = text
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw AIError(friendlyMessage(for: error))
        }
    }

    @available(macOS 26, *)
    private static func friendlyMessage(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return "This is too long for Apple Intelligence. Try a shorter question or a larger model."
        case .guardrailViolation, .refusal:
            return "Apple Intelligence declined to answer this request."
        case .unsupportedLanguageOrLocale:
            return "Apple Intelligence doesn't support this language yet. Try a Claude model."
        case .assetsUnavailable:
            return "Apple Intelligence isn't ready yet. Try again in a few minutes."
        case .rateLimited, .concurrentRequests:
            return "Apple Intelligence is busy. Try again in a moment."
        default:
            return "Apple Intelligence failed: \(error.localizedDescription)"
        }
    }
    #endif
}
