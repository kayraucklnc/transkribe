import Foundation
import Testing
@testable import TranskribeCore

@Suite struct IntentTokenCounterTests {
    @Test func decisionAndActionStreamsShareOneMeetingCounter() async throws {
        let base = FakeAIProvider(budget: 100_000) { _ in "abcdefgh" }
        let meter = IntentTokenCounter()
        let provider = IntentMeteredProvider(base: base, counter: meter)
        let model = base.models[0]
        for _ in 0..<2 {
            var reply = ""
            for try await delta in provider.stream(model: model, system: "rules",
                messages: [AIMessage(role: .user, text: "hello")]) { reply += delta }
            #expect(reply == "abcdefgh")
        }
        let usage = await meter.usage()
        #expect(usage.input == 6)
        #expect(usage.output == 4)
        #expect(usage.total == 10)
        let nextMeeting = IntentTokenCounter()
        #expect(await nextMeeting.usage().total == 0)
    }
}
