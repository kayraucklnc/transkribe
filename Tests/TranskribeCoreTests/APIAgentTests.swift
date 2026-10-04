import Foundation
import Testing
@testable import TranskribeCore

@Suite struct APIAgentTests {
    actor Recorder {
        var bodies: [[String: Any]] = []
        func add(_ body: [String: Any]) { bodies.append(body) }
    }

    @Test func runsToolsUntilTheModelAnswers() async throws {
        let recorder = Recorder()
        let replies: [[String: Any]] = [
            ["stop_reason": "tool_use", "content": [
                ["type": "text", "text": "Let me look."],
                ["type": "tool_use", "id": "t1", "name": "search_conversations", "input": ["query": "fiyat"]],
            ]],
            ["stop_reason": "end_turn", "content": [["type": "text", "text": "Fiyat sayfa başı 200 TL."]]],
        ]
        let counter = Counter()
        var events: [AgentEvent] = []
        let stream = AnthropicAgentLoop.run(
            system: "s", messages: [AIMessage(role: .user, text: "Fiyat?")], tools: MCPServer.tools,
            execute: { name, input in "RESULT \(name) \(input["query"] as? String ?? "")" },
            send: { body in
                await recorder.add(body)
                return replies[await counter.next()]
            }
        )
        for try await event in stream { events.append(event) }

        #expect(events.contains(.toolCall(name: "search_conversations", input: #"{"query":"fiyat"}"#)))
        #expect(events.last == .text("Fiyat sayfa başı 200 TL."))
        let second = await recorder.bodies[1]["messages"] as? [[String: Any]]
        #expect(second?.count == 3) // question, assistant tool call, tool result
        let results = second?.last?["content"] as? [[String: Any]]
        #expect(results?.first?["tool_use_id"] as? String == "t1")
        #expect(results?.first?["content"] as? String == "RESULT search_conversations fiyat")
    }

    @Test func refusalBecomesAFriendlyError() async {
        let stream = AnthropicAgentLoop.run(system: "s", messages: [AIMessage(role: .user, text: "x")], tools: [],
                                            execute: { _, _ in "" }, send: { _ in ["stop_reason": "refusal", "content": []] })
        await #expect(throws: AIError.self) { for try await _ in stream {} }
    }

    actor Counter {
        var value = 0
        func next() -> Int { defer { value += 1 }; return value }
    }
}
