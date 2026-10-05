import Foundation

/// The Claude API tool-use loop: ask, run requested tools locally, send results back, until
/// the model answers. The transport is injected so the loop is testable without network.
public enum AnthropicAgentLoop {
    static let maxRounds = 12

    public typealias Execute = @Sendable (_ name: String, _ input: [String: Any]) async -> String
    public typealias Send = @Sendable (_ body: [String: Any]) async throws -> [String: Any]

    public static func run(system: String, messages: [AIMessage], tools: [[String: Any]],
                           execute: @escaping Execute, send: @escaping Send) -> AsyncThrowingStream<AgentEvent, Error> {
        let toolDefinitions = tools.map { tool -> [String: Any] in
            ["name": tool["name"] ?? "", "description": tool["description"] ?? "", "input_schema": tool["inputSchema"] ?? [:]]
        }
        let conversation = AnthropicAPIProvider.merged(messages).map { ["role": $0.role.rawValue, "content": $0.text] as [String: Any] }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var history = conversation
                    for _ in 0..<maxRounds {
                        try Task.checkCancellation()
                        let reply = try await send([
                            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
                            "messages": history,
                            "tools": toolDefinitions,
                        ])
                        let content = reply["content"] as? [[String: Any]] ?? []
                        switch reply["stop_reason"] as? String {
                        case "refusal":
                            throw AIError("Claude declined to answer this request.")
                        case "tool_use":
                            history.append(["role": "assistant", "content": content])
                            var results: [[String: Any]] = []
                            continuation.yield(.resetText)
                            for call in content where call["type"] as? String == "tool_use" {
                                let name = call["name"] as? String ?? ""
                                let input = call["input"] as? [String: Any] ?? [:]
                                let inputJSON = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                                continuation.yield(.toolCall(name: name, input: inputJSON))
                                let output = await execute(name, input)
                                results.append(["type": "tool_result", "tool_use_id": call["id"] ?? "", "content": output])
                            }
                            history.append(["role": "user", "content": results])
                        default:
                            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
                            continuation.yield(.text(text))
                            continuation.finish()
                            return
                        }
                    }
                    throw AIError("The assistant took too many steps. Try a more specific question.")
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension AnthropicAPIProvider {
    /// Claude with the conversation tools, through the API key (non-streaming rounds).
    public func agent(model: AIModel, system: String, messages: [AIMessage],
                      execute: @escaping AnthropicAgentLoop.Execute) -> AsyncThrowingStream<AgentEvent, Error> {
        let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = self.session
        return AnthropicAgentLoop.run(system: system, messages: messages, tools: MCPServer.tools, execute: execute) { body in
            guard let key, !key.isEmpty else { throw AIError(Self.noKeyReason) }
            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            var payload = body
            payload["model"] = model.id
            payload["max_tokens"] = 16_000
            if Self.currentGenerationModels.contains(model.id) {
                request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
                payload["output_config"] = ["effort": "medium"]
                payload["fallbacks"] = "default"
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw AIError(Self.errorMessage(status: status, body: data)) }
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
    }
}
