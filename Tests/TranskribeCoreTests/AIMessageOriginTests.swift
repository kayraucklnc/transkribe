import Foundation
import Testing
@testable import TranskribeCore

@Suite struct AIMessageOriginTests {
    @Test func oldChatsDecodeAndAgentMetadataRoundTrips() throws {
        let old = try JSONDecoder().decode(AIChat.self,
            from: Data(#"{"messages":[{"role":"assistant","text":"Old answer"}]}"#.utf8))
        #expect(old.messages.first?.origin == nil)
        #expect(old.messages.first?.answerId == nil)
        let message = AIMessage(role: .assistant, text: "Agent answer", origin: .agent, answerId: UUID())
        let decoded = try JSONDecoder().decode(AIMessage.self, from: JSONEncoder().encode(message))
        #expect(decoded == message)
    }
}
