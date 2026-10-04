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
