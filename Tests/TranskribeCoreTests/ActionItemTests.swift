import Foundation
import Testing
@testable import TranskribeCore

@Suite struct ActionItemTests {
    let model = AIModel(provider: .claudeCode, id: "fake", displayName: "Fake")

    @Test func parsesTheModelsListEvenWithExtraText() throws {
        let reply = """
        Here are the to-dos:
        ```json
        [{"task": "Send the proposal", "owner": "Me", "due": "Friday", "time": "2:15"},
         {"task": "Teklifi incele", "owner": "Hakan", "due": null, "time": "1:02:03"}]
        ```
        """
        let items = try ActionItems.parse(reply)
        #expect(items.map(\.task) == ["Send the proposal", "Teklifi incele"])
        #expect(items[0].owner == "Me")
        #expect(items[0].due == "Friday")
        #expect(items[0].time == 135)
        #expect(items[1].due == nil)
        #expect(items[1].time == 3723)
    }

    @Test func noneIsAnEmptyList() throws {
        #expect(try ActionItems.parse("[]").isEmpty)
        #expect(throws: AIError.self) { try ActionItems.parse("I couldn't find any.") }
    }

    @Test func asksInTheConversationsLanguageAndCollectsAllParts() async throws {
        var transcript = Fixtures.transcript(segments: (0..<120).map {
            Segment(start: Double($0) * 30, end: Double($0) * 30 + 5, text: "Rutin güncelleme numara \($0).", speaker: $0 % 2 + 1)
        })
        transcript.language = "tr"
        let provider = FakeAIProvider(budget: 2_000) { call in
            call.messages[0].text.contains("numara 0.") ? #"[{"task":"Sözleşmeyi gönder","owner":"Speaker 1","due":null,"time":"0:00"}]"# : "[]"
        }
        let items = try await ActionItems.extract(from: transcript, provider: provider, model: model)
        #expect(items.map(\.task) == ["Sözleşmeyi gönder"])
        #expect(provider.calls.count > 1)
        #expect(provider.calls[0].system.contains("Turkish"))
    }
}
