import Foundation
import Testing
@testable import TranskribeCore

/// Talks to real backends (and the real keychain), so it is opt-in:
/// `TRANSKRIBE_AI_SMOKE=1 swift test --filter AISmokeTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_AI_SMOKE"] == "1"), .serialized)
struct AISmokeTests {
    @Test func claudeCodeStreams() async throws {
        let provider = ClaudeCodeProvider()
        #expect(await provider.availability() == .available)
        var deltas: [String] = []
        let stream = provider.stream(
            model: ClaudeCodeProvider.haiku,
            system: "Reply in Turkish, in one short sentence.",
            messages: [AIMessage(role: .user, text: "Say hello and name one Turkish city.")]
        )
        for try await delta in stream { deltas.append(delta) }
        print("[smoke] Claude Code deltas (\(deltas.count)): \(deltas)")
        #expect(deltas.count > 1)
        #expect(!deltas.joined().isEmpty)
    }

    @Test func claudeCodeCancels() async throws {
        let provider = ClaudeCodeProvider()
        let stream = provider.stream(
            model: ClaudeCodeProvider.haiku,
            system: "You write long text.",
            messages: [AIMessage(role: .user, text: "Count from 1 to 300, one number per line.")]
        )
        var received = 0
        for try await _ in stream {
            received += 1
            if received == 3 { break }
        }
        #expect(received == 3)
    }

    @Test func summarizesTurkishMeetingWithClaudeCode() async throws {
        var transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 6, text: "Günaydın. Bugün lansman tarihini ve bütçeyi konuşalım.", speaker: 1),
            Segment(start: 7, end: 14, text: "Tasarım ekibi iki hafta gecikti, Mart'a kaydırmamız lazım.", speaker: 2),
            Segment(start: 15, end: 20, text: "Tamam, lansmanı 15 Mart'a alıyoruz. Pazarlama bütçesi ne durumda?", speaker: 1),
            Segment(start: 21, end: 30, text: "Yüzde on artış istiyoruz. Rakamları cumaya kadar ben gönderirim.", speaker: 2),
            Segment(start: 31, end: 36, text: "Ajansla sözleşmeyi kim yenileyecek, henüz belli değil.", speaker: 1),
        ])
        transcript.speakerNames = [1: "Ayşe"]
        var summary = ""
        for try await delta in Summarizer.summarize(transcript: transcript, provider: ClaudeCodeProvider(), model: ClaudeCodeProvider.haiku) {
            summary += delta
        }
        print("[smoke] Summary:\n\(summary)")
        #expect(summary.contains("[0:"))
    }

    @Test func appleIntelligenceStreamsWhenAvailable() async throws {
        let provider = AppleIntelligenceProvider()
        let availability = await provider.availability()
        print("[smoke] Apple Intelligence availability: \(availability)")
        guard availability == .available else { return }
        var text = ""
        for try await delta in provider.stream(model: AppleIntelligenceProvider.model, system: "Be brief.", messages: [AIMessage(role: .user, text: "Say hello.")]) {
            text += delta
        }
        print("[smoke] Apple Intelligence: \(text)")
        #expect(!text.isEmpty)
    }

    @Test func keychainRoundTrip() throws {
        let store = KeychainStore(service: "kayrauckilinc.dev.transkribe.tests")
        let account = "smoke-\(UUID().uuidString)"
        try store.set("first", account: account)
        try store.set("second", account: account)
        #expect(store.get(account: account) == "second")
        try store.delete(account: account)
        #expect(store.get(account: account) == nil)
        try store.delete(account: account)
    }
}
