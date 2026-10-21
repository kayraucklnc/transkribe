import Foundation
import Testing
@testable import TranskribeCore

@Suite struct AIMessageOriginTests {
    @Test func recordingEndTimeIsOptionalAndPersists() throws {
        var transcript = Transcript(title: "Meeting", tracks: [])
        let old = try JSONEncoder().encode(transcript)
        #expect(try JSONDecoder().decode(Transcript.self, from: old).recordingEndedAt == nil)
        transcript.recordingEndedAt = Date(timeIntervalSince1970: 1_000_000)
        #expect(try JSONDecoder().decode(Transcript.self, from: JSONEncoder().encode(transcript)).recordingEndedAt == transcript.recordingEndedAt)
    }

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
