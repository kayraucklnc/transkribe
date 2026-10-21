import Foundation

/// Streams answers from the xAI Responses API.
public struct XAIProvider: AIProvider {
    public static let grok = AIModel(provider: .xai, id: "grok-4.3", displayName: "Grok 4.3 (fast)")
    public static let keychainAccount = "xai-api-key"
    private static let noKeyReason = "Add an xAI API key in Settings."
    private static let endpoint = URL(string: "https://api.x.ai/v1/responses")!

    public let kind = AIProviderKind.xai
    public var models: [AIModel] { [Self.grok] }
    private let apiKey: @Sendable () -> String?
    private let session: URLSession

    /// Reads the key from Keychain unless a key supplier is given.
    public init(session: URLSession = .shared, apiKey: (@Sendable () -> String?)? = nil) {
        self.session = session
        self.apiKey = apiKey ?? { KeychainStore().get(account: Self.keychainAccount) }
    }

    public func contextCharacterBudget(for model: AIModel) -> Int { 500_000 }

    public func availability() async -> AIAvailability {
        currentKey() == nil ? .unavailable(reason: Self.noKeyReason) : .available
    }

    public func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        let key = currentKey()
        let session = session
        return AIStreaming.run { yield in
            guard let key else { throw AIError(Self.noKeyReason) }
            let request = try Self.makeRequest(key: key, model: model, system: system, messages: messages)
            do {
                try await Self.send(request, session: session, yield: yield)
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                throw AIError("Cannot reach xAI. Check your connection and try again.")
            }
        }
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
            "store": false,
            "reasoning": ["effort": "none"],
            "tools": [["type": "web_search"], ["type": "x_search"]],
            "input": [["role": "system", "content": system]]
                + messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ])
        return request
    }

    private static func send(_ request: URLRequest, session: URLSession, yield: @Sendable (String) -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError(httpError(status: status)) }
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let data = Data(line.dropFirst(5).utf8)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw AIError("xAI returned an invalid stream event.")
            }
            switch object["type"] as? String {
            case "response.output_text.delta":
                if let delta = object["delta"] as? String { yield(delta) }
            case "response.completed":
                return
            case "response.failed":
                let response = object["response"] as? [String: Any]
                let error = response?["error"] as? [String: Any]
                throw AIError(streamError(code: error?["code"] as? String))
            case "error":
                throw AIError(streamError(code: object["code"] as? String))
            case "response.incomplete":
                throw AIError("xAI stopped before the answer was complete. Try a shorter question.")
            case "response.refusal.delta", "response.refusal.done":
                throw AIError("Grok declined to answer this request.")
            default:
                continue
            }
        }
        throw AIError("The xAI stream ended before the answer was complete. Try again.")
    }

    private static func httpError(status: Int) -> String {
        switch status {
        case 400: "xAI rejected the request. Check the model and transcript length."
        case 401: "xAI rejected your API key. Check it in Settings."
        case 403: "Your xAI API key cannot use this model."
        case 404: "This model is unavailable with your xAI API key."
        case 413: "This transcript is too long to send to xAI."
        case 429: "You reached the xAI rate limit. Wait a minute and try again."
        case 500...599: "xAI has a server error. Try again later."
        default: "xAI returned an HTTP error (\(status))."
        }
    }

    private static func streamError(code: String?) -> String {
        // Server messages can contain request data. Show only fixed error descriptions.
        switch code {
        case "rate_limit_exceeded", "rate_limit_error": httpError(status: 429)
        case "invalid_api_key", "authentication_error": httpError(status: 401)
        case "server_error", "api_error": httpError(status: 500)
        default: "xAI could not complete the answer. Try again."
        }
    }
}
