import Foundation
import Testing
@testable import TranskribeCore

@Suite(.serialized) struct WebhookTests {
    private let eventId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let conversationId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let startedAt = Date(timeIntervalSince1970: 0)

    @Test(arguments: ["meeting.started", "meeting.ended"])
    func meetingPayloadIsStable(type: String) throws {
        let event = WebhookEvent(type: try #require(WebhookEvent.EventType(rawValue: type)),
            eventId: eventId, conversationId: conversationId, title: "Weekly sync", startedAt: startedAt)
        let expected = """
        {"conversationId":"22222222-2222-2222-2222-222222222222","eventId":"11111111-1111-1111-1111-111111111111","startedAt":"1970-01-01T00:00:00Z","title":"Weekly sync","type":"\(type)","version":1}
        """
        #expect(String(decoding: try event.encoded(), as: UTF8.self) == expected)
        #expect(try event.encoded() == event.encoded())
    }

    @Test func intentPayloadKeepsInstructionSeparateFromHeardData() throws {
        let intent = WebhookEvent.Intent(id: "explicit-ask", instruction: "Research the quoted request.",
            request: "Grok, compare Acme", context: "[00:10] Me: Grok, compare Acme")
        let event = WebhookEvent(type: .intent, eventId: eventId, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt, intent: intent)
        let expected = #"{"conversationId":"22222222-2222-2222-2222-222222222222","eventId":"11111111-1111-1111-1111-111111111111","intent":{"context":"[00:10] Me: Grok, compare Acme","id":"explicit-ask","instruction":"Research the quoted request.","request":"Grok, compare Acme"},"startedAt":"1970-01-01T00:00:00Z","title":"Weekly sync","type":"intent","version":1}"#
        #expect(String(decoding: try event.encoded(), as: UTF8.self) == expected)
    }
}
