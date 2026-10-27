import Foundation

/// Streams answers from the OpenRouter Chat Completions API.
public struct OpenRouterProvider: AIProvider {
    // Model IDs were verified with GET /api/v1/models on 2026-10-22.
    public static let grok = AIModel(provider: .openRouter, id: "x-ai/grok-4.3", displayName: "Grok 4.3 (OpenRouter)")
    public static let haiku = AIModel(provider: .openRouter, id: "anthropic/claude-haiku-5.5", displayName: "Claude Haiku 5.5 (OpenRouter)")
    public static let luna = AIModel(provider: .openRouter, id: "openai/gpt-6-luna", displayName: "GPT-6 Luna (OpenRouter)")
    public static let keychainAccount = OpenRouterKeychain.account
    private static let noKeyReason = "Add an OpenRouter API key in Settings."
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    public let kind = AIProviderKind.openRouter
    public var models: [AIModel] { [Self.grok, Self.haiku, Self.luna] }
    private let apiKey: @Sendable () -> String?
    private let session: URLSession

    public init(session: URLSession = .shared, apiKey: (@Sendable () -> String?)? = nil) {
        self.session = session
        self.apiKey = apiKey ?? { KeychainStore().get(account: Self.keychainAccount) }
    }

    public func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        let key = currentKey()
        let session = session
        return AIStreaming.run { yield in
            guard let key else { throw AIError(Self.noKeyReason) }
            try Task.checkCancellation()
            let request = try Self.makeRequest(key: key, model: model, system: system, messages: messages)
            do {
                try await Self.send(request, session: session, yield: yield)
            } catch let error as URLError {
                if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
                throw AIError("Cannot reach OpenRouter. Check your connection and try again.")
            }
        }
    }

    public func contextCharacterBudget(for model: AIModel) -> Int { 500_000 }

    public func availability() async -> AIAvailability {
        currentKey() == nil ? .unavailable(reason: Self.noKeyReason) : .available
    }

    private func currentKey() -> String? {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    private static func makeRequest(key: String, model: AIModel, system: String, messages: [AIMessage]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.id,
            "stream": true,
            "reasoning": ["effort": "none"],
            "messages": [["role": "system", "content": system]]
                + messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ])
        return request
    }

    private static func send(_ request: URLRequest, session: URLSession, yield: @Sendable (String) -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError(httpError(status: status)) }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { return }
            guard let object = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else {
                throw AIError("OpenRouter returned an invalid stream event.")
            }
            if let error = object["error"] as? [String: Any] {
                throw AIError((error["code"] as? Int).map { httpError(status: $0) }
                    ?? "OpenRouter could not complete the answer. Try again.")
            }
            guard let choices = object["choices"] as? [[String: Any]] else {
                throw AIError("OpenRouter returned an invalid stream event.")
            }
            switch choices.first?["finish_reason"] as? String {
            case "error":
                throw AIError("OpenRouter could not complete the answer. Try again.")
            case "length":
                throw AIError("OpenRouter stopped before the answer was complete. Try a shorter question.")
            case "content_filter":
                throw AIError("The OpenRouter model declined to answer this request.")
            default:
                break
            }
            if let delta = choices.first?["delta"] as? [String: Any],
               let text = delta["content"] as? String, !text.isEmpty {
                yield(text)
            }
        }
        throw AIError("The OpenRouter stream ended before the answer was complete. Try again.")
    }

    private static func httpError(status: Int) -> String {
        // Server content can contain keys or transcript text. Use fixed descriptions.
        switch status {
        case 400: "OpenRouter rejected the request. Check the model and transcript length."
        case 401: "OpenRouter rejected your API key. Check it in Settings."
        case 402: "Your OpenRouter credits are insufficient. Add credits to your account."
        case 403: "Your OpenRouter API key cannot use this model."
        case 404: "This model is unavailable through OpenRouter."
        case 429: "You reached the OpenRouter rate limit. Wait a minute and try again."
        case 500...599: "OpenRouter has a server error. Try again later."
        default: "OpenRouter returned an HTTP error (\(status))."
        }
    }
}
