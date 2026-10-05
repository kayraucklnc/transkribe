import Foundation
import Testing
@testable import TranskribeCore

private func jsonBody(of request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite struct AnthropicSSEParserTests {
    @Test func parsesTextDeltas() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Merhaba ğüşİ"}}"#
        #expect(AnthropicSSEParser.parse(line: line) == .textDelta("Merhaba ğüşİ"))
    }

    @Test func ignoresNonTextBlocksAndEventLines() {
        let lines = [
            "event: content_block_delta",
            "",
            #"data: {"type":"ping"}"#,
            #"data: {"type":"message_start","message":{"id":"msg_1","model":"claude-opus-5-5"}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"fallback","from":{"model":"a"},"to":{"model":"b"}}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"x"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            "data: not json",
        ]
        #expect(lines.compactMap(AnthropicSSEParser.parse(line:)).isEmpty)
    }

    @Test func parsesStopReasonsMessageStopAndErrors() {
        #expect(AnthropicSSEParser.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":null}},"usage":{"output_tokens":3}}"#) == .stopReason("refusal"))
        #expect(AnthropicSSEParser.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":null},"usage":{}}"#) == nil)
        #expect(AnthropicSSEParser.parse(line: #"data: {"type":"message_stop"}"#) == .messageStop)
        #expect(AnthropicSSEParser.parse(line: #"data:{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
            == .error(type: "overloaded_error", message: "Overloaded"))
    }

    @Test func mapsHTTPErrorsToFriendlyMessages() {
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"messages: field required"}}"#.utf8)
        #expect(AnthropicAPIProvider.errorMessage(status: 401, body: Data()) == "Your Anthropic API key was rejected. Check it in Settings.")
        #expect(AnthropicAPIProvider.errorMessage(status: 429, body: Data()).contains("rate limit"))
        #expect(AnthropicAPIProvider.errorMessage(status: 529, body: Data()).contains("overloaded"))
        #expect(AnthropicAPIProvider.errorMessage(status: 400, body: body) == "Anthropic rejected the request: messages: field required")
        #expect(AnthropicAPIProvider.friendlyMessage(errorType: "rate_limit_error", message: nil).contains("rate limit"))
    }

    @Test func buildsRequestWithFallbacksForCurrentModels() throws {
        let messages = [AIMessage(role: .user, text: "a"), AIMessage(role: .user, text: "b"), AIMessage(role: .assistant, text: "c"), AIMessage(role: .user, text: "d")]
        let request = try AnthropicAPIProvider.makeRequest(apiKey: "sk-test", model: "claude-opus-5-5", system: "SYS", messages: messages)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try jsonBody(of: request)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["max_tokens"] as? Int == 64_000)
        #expect(body["stream"] as? Bool == true)
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: String]) == ["effort": "medium"])
        let system = try #require(body["system"] as? [[String: Any]])
        #expect(system.first?["text"] as? String == "SYS")
        #expect((system.first?["cache_control"] as? [String: String]) == ["type": "ephemeral"])
        let sent = try #require(body["messages"] as? [[String: String]])
        #expect(sent == [["role": "user", "content": "a\n\nb"], ["role": "assistant", "content": "c"], ["role": "user", "content": "d"]])
    }

    @Test func haikuRequestHasNoFallbackOrEffort() throws {
        let request = try AnthropicAPIProvider.makeRequest(apiKey: "k", model: "claude-haiku-4-5", system: "s", messages: [AIMessage(role: .user, text: "hi")])
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let body = try jsonBody(of: request)
        #expect(body["fallbacks"] == nil)
        #expect(body["output_config"] == nil)
    }

    @Test func availabilityAndBudgets() async {
        let withKey = AnthropicAPIProvider(apiKey: { "sk-ant" })
        let withoutKey = AnthropicAPIProvider(apiKey: { "  " })
        #expect(await withKey.availability() == .available)
        #expect(await withoutKey.availability() == .unavailable(reason: "Add an Anthropic API key in Settings."))
        #expect(withKey.models.map(\.id) == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"])
        #expect(withKey.contextCharacterBudget(for: AnthropicAPIProvider.opus) == 2_500_000)
        #expect(withKey.contextCharacterBudget(for: AnthropicAPIProvider.haiku) == 500_000)
    }

    @Test func missingKeyFailsTheStream() async {
        let provider = AnthropicAPIProvider(apiKey: { nil })
        await #expect(throws: AIError("Add an Anthropic API key in Settings.")) {
            for try await _ in provider.stream(model: AnthropicAPIProvider.opus, system: "", messages: [AIMessage(role: .user, text: "hi")]) {}
        }
    }
}

@Suite struct ClaudeCodeStreamParserTests {
    @Test func parsesTextDeltas() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Selam"}},"session_id":"s","parent_tool_use_id":null,"uuid":"u"}"#
        #expect(ClaudeCodeStreamParser.parse(line: line) == .textDelta("Selam"))
    }

    @Test func ignoresOtherLines() {
        let lines = [
            #"{"type":"system","subtype":"init","model":"claude-haiku-4-5"}"#,
            #"{"type":"stream_event","event":{"type":"message_start","message":{}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"x"}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Selam"}]}}"#,
            "",
            "garbage",
        ]
        #expect(lines.compactMap(ClaudeCodeStreamParser.parse(line:)).isEmpty)
    }

    @Test func parsesResults() {
        #expect(ClaudeCodeStreamParser.parse(line: #"{"type":"result","subtype":"success","is_error":false,"result":"Selam"}"#)
            == .result(text: "Selam", isError: false))
        #expect(ClaudeCodeStreamParser.parse(line: #"{"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login"}"#)
            == .result(text: "Invalid API key · Please run /login", isError: true))
        #expect(ClaudeCodeStreamParser.parse(line: #"{"type":"result","subtype":"error_during_execution","is_error":true}"#)
            == .result(text: "error_during_execution", isError: true))
    }

    @Test func friendlyErrorForSignedOutCLI() {
        #expect(ClaudeCodeProvider.friendlyMessage(forResult: "Invalid API key · Please run /login").contains("isn't signed in"))
        #expect(ClaudeCodeProvider.friendlyMessage(forResult: "Something odd") == "Claude Code: Something odd")
    }

    @Test func buildsArgumentsAndEnvironment() {
        let args = ClaudeCodeProvider.arguments(model: "haiku", system: .inline("SYS"))
        #expect(args == ["-p", "--model", "haiku", "--tools", "", "--system-prompt", "SYS", "--output-format", "stream-json",
                         "--include-partial-messages", "--verbose", "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config"])
        let fileArgs = ClaudeCodeProvider.arguments(model: "opus", system: .file(URL(fileURLWithPath: "/tmp/s.txt")))
        #expect(fileArgs.contains("--system-prompt-file"))
        #expect(!fileArgs.contains("--system-prompt"))

        let env = ClaudeCodeProvider.environment(
            from: ["CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "CLAUDE_CODE_SESSION_ID": "x", "CLAUDE_CODE_CHILD_SESSION": "1", "HOME": "/Users/me", "PATH": "/usr/bin"],
            executable: URL(fileURLWithPath: "/custom/bin/claude")
        )
        #expect(env["CLAUDECODE"] == nil && env["CLAUDE_CODE_ENTRYPOINT"] == nil && env["CLAUDE_CODE_SESSION_ID"] == nil && env["CLAUDE_CODE_CHILD_SESSION"] == nil)
        #expect(env["HOME"] == "/Users/me")
        #expect(env["PATH"]?.hasPrefix("/usr/bin:/custom/bin") == true)
    }

    @Test func rendersMultiTurnConversationAsOnePrompt() {
        #expect(ConversationRenderer.prompt(from: [AIMessage(role: .user, text: "Q")]) == "Q")
        let prompt = ConversationRenderer.prompt(from: [
            AIMessage(role: .user, text: "Q1"), AIMessage(role: .assistant, text: "A1"), AIMessage(role: .user, text: "Q2"),
        ])
        #expect(prompt.contains("<user>\nQ1\n</user>\n<assistant>\nA1\n</assistant>"))
        #expect(prompt.hasSuffix("Q2"))
    }

    @Test func missingExecutableFailsTheStream() async {
        let provider = ClaudeCodeProvider(executableURL: URL(fileURLWithPath: "/nonexistent/claude"))
        await #expect(throws: AIError.self) {
            for try await _ in provider.stream(model: ClaudeCodeProvider.haiku, system: "", messages: [AIMessage(role: .user, text: "hi")]) {}
        }
    }
}

@Suite struct AppleIntelligenceProviderTests {
    @Test func snapshotDeltas() {
        #expect(AppleIntelligenceProvider.delta(from: "", to: "Mer") == "Mer")
        #expect(AppleIntelligenceProvider.delta(from: "Mer", to: "Merhaba") == "haba")
        #expect(AppleIntelligenceProvider.delta(from: "Merhaba", to: "Merhaba") == "")
        #expect(AppleIntelligenceProvider.delta(from: "Merhabx", to: "Merhaba dünya") == "a dünya")
    }

    @Test func describesItself() {
        let provider = AppleIntelligenceProvider()
        #expect(provider.models == [AppleIntelligenceProvider.model])
        #expect(provider.models[0].displayName == "Apple Intelligence (on-device)")
        #expect(provider.contextCharacterBudget(for: AppleIntelligenceProvider.model) == 6_000)
    }
}
