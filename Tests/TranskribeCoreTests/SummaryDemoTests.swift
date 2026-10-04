import Foundation
import Testing
@testable import TranskribeCore

/// Summarizes a real stored transcript with Claude Code: TRANSKRIBE_SUMMARY_FILE=/path/transcript.json
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_SUMMARY_FILE"] != nil))
struct SummaryDemoTests {
    @Test func summarizeStoredTranscript() async throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRANSKRIBE_SUMMARY_FILE"]!)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(Transcript.self, from: Data(contentsOf: url))
        var text = ""
        let start = Date()
        for try await delta in Summarizer.summarize(transcript: transcript, provider: ClaudeCodeProvider(), model: ClaudeCodeProvider.sonnet) {
            text += delta
        }
        print("SUMMARY_SECONDS", Int(Date().timeIntervalSince(start)))
        try text.write(to: URL(fileURLWithPath: "/tmp/transkribe-summary.md"), atomically: true, encoding: .utf8)
        #expect(!text.isEmpty)
    }
}

/// Finds to-dos in a real stored transcript with Claude Code: TRANSKRIBE_SUMMARY_FILE=/path/transcript.json
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_SUMMARY_FILE"] != nil))
struct ActionItemsDemoTests {
    @Test func findToDosInStoredTranscript() async throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRANSKRIBE_SUMMARY_FILE"]!)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(Transcript.self, from: Data(contentsOf: url))
        let items = try await ActionItems.extract(from: transcript, provider: ClaudeCodeProvider(), model: ClaudeCodeProvider.sonnet)
        for item in items { print("TODO", item.task, "|", item.owner ?? "-", "|", item.due ?? "-", "|", item.time.map(TranscriptFormatter.timestamp) ?? "-") }
        #expect(!items.isEmpty)
    }
}

/// Expands a search with Apple Intelligence and runs it on the real library: TRANSKRIBE_MEANING_QUERY=money
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_MEANING_QUERY"] != nil))
struct MeaningSearchDemoTests {
    @Test func expandAndSearchLibrary() async throws {
        let query = ProcessInfo.processInfo.environment["TRANSKRIBE_MEANING_QUERY"]!
        let useApple = ProcessInfo.processInfo.environment["TRANSKRIBE_MEANING_APPLE"] == "1"
        let provider: any AIProvider = useApple ? AppleIntelligenceProvider() : ClaudeCodeProvider()
        let model = useApple ? try #require(provider.models.first) : ClaudeCodeProvider.haiku
        var reply = ""
        for try await delta in provider.stream(model: model, system: MeaningSearch.system(languages: ["en", "tr", "it"]),
                                               messages: [AIMessage(role: .user, text: query)]) { reply += delta }
        let terms = MeaningSearch.parseTerms(reply, query: query)
        print("TERMS", terms)
        let library = ConversationLibrary.load()
        for transcript in MeaningSearch.rank(library.transcripts, terms: terms) {
            let hits = MeaningSearch.hits(in: transcript, terms: terms)
            print("HIT", transcript.title, hits.count, hits.first?.text ?? "")
        }
        #expect(terms.count > 1)
    }
}
