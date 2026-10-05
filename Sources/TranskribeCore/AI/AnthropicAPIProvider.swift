import Foundation

/// Calls the Anthropic Messages API directly with the user's API key, streaming over SSE.
public struct AnthropicAPIProvider: AIProvider {
    public static let opus = AIModel(provider: .anthropicAPI, id: "claude-opus-5-5", displayName: "Claude Opus 5.5")
    public static let sonnet = AIModel(provider: .anthropicAPI, id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5")
    public static let haiku = AIModel(provider: .anthropicAPI, id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5")
    /// Keychain account holding the API key (service `KeychainStore.defaultService`).
    public static let keychainAccount = "anthropic-api-key"

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let maxTokens = 64_000
    /// Models that take server-side refusal fallbacks and `output_config.effort` (Haiku 4.5 rejects effort).
    static let currentGenerationModels: Set<String> = [opus.id, sonnet.id]
    static let noKeyReason = "Add an Anthropic API key in Settings."

    public let kind = AIProviderKind.anthropicAPI
    public var models: [AIModel] { [Self.opus, Self.sonnet, Self.haiku] }

    let apiKey: @Sendable () -> String?
    let session: URLSession

    /// - Parameter apiKey: supplies the key; reads it from the keychain when nil.
    public init(session: URLSession = .shared, apiKey: (@Sendable () -> String?)? = nil) {
        self.session = session
        self.apiKey = apiKey ?? { KeychainStore().get(account: AnthropicAPIProvider.keychainAccount) }
    }

    public func contextCharacterBudget(for model: AIModel) -> Int {
        Self.currentGenerationModels.contains(model.id) ? 2_500_000 : 500_000
    }

    public func availability() async -> AIAvailability {
        currentKey() == nil ? .unavailable(reason: Self.noKeyReason) : .available
    }

    public func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        let key = currentKey()
        let session = session
        return AIStreaming.run { yield in
            guard let key else { throw AIError(Self.noKeyReason) }
            let request = try Self.makeRequest(apiKey: key, model: model.id, system: system, messages: messages)
            do {
                try await Self.send(request, session: session, yield: yield)
            } catch let error as URLError where error.code != .cancelled {
                throw AIError("Couldn't reach Anthropic: \(error.localizedDescription)")
            }
        }
    }

    private func currentKey() -> String? {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    private static func send(_ request: URLRequest, session: URLSession, yield: @Sendable (String) -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 65_536 { break }
            }
            throw AIError(errorMessage(status: status, body: body))
        }
        for try await line in bytes.lines {
            switch AnthropicSSEParser.parse(line: line) {
            case .textDelta(let text):
                yield(text)
            case .stopReason(let reason) where reason == "refusal":
                throw AIError("Claude declined to answer this request.")
            case .error(let type, let message):
                throw AIError(friendlyMessage(errorType: type, message: message))
            case .messageStop:
                return
            case .stopReason, nil:
                continue
            }
        }
    }

    // MARK: - Request

    static func makeRequest(apiKey: String, model: String, system: String, messages: [AIMessage]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let isCurrent = currentGenerationModels.contains(model)
        if isCurrent {
            request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": merged(messages).map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if isCurrent {
            body["output_config"] = ["effort": "medium"]
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The API needs alternating roles; join consecutive messages from the same side.
    static func merged(_ messages: [AIMessage]) -> [AIMessage] {
        messages.reduce(into: [AIMessage]()) { result, message in
            if let last = result.last, last.role == message.role {
                result[result.count - 1].text += "\n\n" + message.text
            } else {
                result.append(message)
            }
        }
    }

    // MARK: - Errors

    static func errorMessage(status: Int, body: Data) -> String {
        let error = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? [String: Any]
        let message = error?["message"] as? String
        switch status {
        case 400:
            return "Anthropic rejected the request" + (message.map { ": \($0)" } ?? ".")
        case 401:
            return "Your Anthropic API key was rejected. Check it in Settings."
        case 403:
            return "Your Anthropic API key isn't allowed to use this model."
        case 404:
            return "This model isn't available with your Anthropic API key."
        case 413:
            return "This transcript is too long to send to Anthropic in one request."
        case 429:
            return "You've hit Anthropic's rate limit. Wait a minute and try again."
        case 500..<529:
            return "Anthropic had a server error. Try again in a moment."
        case 529:
            return "Anthropic's servers are overloaded right now. Try again in a moment."
        default:
            return "Anthropic returned an error (\(status))" + (message.map { ": \($0)" } ?? ".")
        }
    }

    static func friendlyMessage(errorType: String?, message: String?) -> String {
        switch errorType {
        case "overloaded_error":
            return "Anthropic's servers are overloaded right now. Try again in a moment."
        case "rate_limit_error":
            return "You've hit Anthropic's rate limit. Wait a minute and try again."
        case "authentication_error":
            return "Your Anthropic API key was rejected. Check it in Settings."
        case "permission_error":
            return "Your Anthropic API key isn't allowed to use this model."
        case "request_too_large":
            return "This transcript is too long to send to Anthropic in one request."
        case "api_error":
            return "Anthropic had a server error. Try again in a moment."
        default:
            return "Anthropic returned an error" + (message.map { ": \($0)" } ?? ".")
        }
    }
}

/// Parses the lines of a Messages API server-sent event stream. Only `data:` lines carry
/// information; `event:` lines repeat the `type` field and are ignored.
public enum AnthropicSSEParser {
    public enum Event: Equatable, Sendable {
        case textDelta(String)
        case stopReason(String)
        case error(type: String?, message: String?)
        case messageStop
    }

    public static func parse(line: String) -> Event? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        switch type {
        case "content_block_delta":
            // Thinking, signature and other block deltas are skipped; only visible text is yielded.
            guard let delta = object["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .textDelta(text)
        case "message_delta":
            guard let reason = (object["delta"] as? [String: Any])?["stop_reason"] as? String else { return nil }
            return .stopReason(reason)
        case "message_stop":
            return .messageStop
        case "error":
            let error = object["error"] as? [String: Any]
            return .error(type: error?["type"] as? String, message: error?["message"] as? String)
        default:
            // message_start, content_block_start/stop (incl. `fallback` blocks), ping
            return nil
        }
    }
}
