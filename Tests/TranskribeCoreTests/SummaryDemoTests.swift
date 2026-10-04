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

/// Runs mic speaker detection on a real Mic + System recording: TRANSKRIBE_MIC_DIR=/path/to/recording-folder
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_MIC_DIR"] != nil))
struct MicSpeakersDemoTests {
    @Test func separateVoicesOnARealMicrophone() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRANSKRIBE_MIC_DIR"]!)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(Transcript.self, from: Data(contentsOf: folder.appendingPathComponent("transcript.json")))
        let mic = try #require(transcript.tracks.first { $0.source == .microphone })
        let samples = try await AudioDecoder.decode(url: folder.appendingPathComponent(mic.fileName))
        let turns = try await DiarizationEngine().turns(samples: samples)
        let talk = turns.reduce(into: [Int: Double]()) { $0[$1.speaker, default: 0] += $1.end - $1.start }
        print("MIC TALK", talk.mapValues { Int($0) })
        let micLines = transcript.segments.filter { $0.speaker == SpeakerID.me }.map {
            RawSegment(start: $0.start - mic.offset, end: $0.end - mic.offset, text: $0.text, words: [])
        }
        let call = transcript.segments.filter { !SpeakerID.isOnMicrophone($0.speaker) }.map { (start: $0.start - mic.offset, end: $0.end - mic.offset) }
        let labeled = MicSpeakers.labelWithCall(micLines, turns: turns, callSpeech: call)
        let counts = labeled.reduce(into: [Int: Int]()) { $0[$1.speaker ?? -1, default: 0] += 1 }
        print("MIC LABELS", counts)
        for line in labeled where line.speaker != SpeakerID.me { print("ROOM", line.text) }
    }
}
