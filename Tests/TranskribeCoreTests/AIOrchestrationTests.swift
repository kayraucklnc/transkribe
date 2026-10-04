import Foundation
import Testing
@testable import TranskribeCore

/// Records requests and answers with scripted text, streamed in a few pieces.
final class FakeAIProvider: AIProvider, @unchecked Sendable {
    struct Call {
        var system: String
        var messages: [AIMessage]
    }

    let kind = AIProviderKind.claudeCode
    let models = [AIModel(provider: .claudeCode, id: "fake", displayName: "Fake")]
    let budget: Int
    private let reply: @Sendable (Call) throws -> String
    private let lock = NSLock()
    private var recorded: [Call] = []

    init(budget: Int, reply: @escaping @Sendable (Call) throws -> String) {
        self.budget = budget
        self.reply = reply
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func contextCharacterBudget(for model: AIModel) -> Int { budget }
    func availability() async -> AIAvailability { .available }

    func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        let call = Call(system: system, messages: messages)
        lock.lock()
        recorded.append(call)
        lock.unlock()
        return AsyncThrowingStream { continuation in
            do {
                let text = try reply(call)
                let middle = text.index(text.startIndex, offsetBy: text.count / 2)
                continuation.yield(String(text[..<middle]))
                continuation.yield(String(text[middle...]))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func append(_ value: Double) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
}

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
    var text = ""
    for try await delta in stream { text += delta }
    return text
}

private func longTranscript(lines: Int = 120) -> Transcript {
    var transcript = Fixtures.transcript(segments: (0..<lines).map { index in
        Segment(start: Double(index) * 40, end: Double(index) * 40 + 5,
                text: index == 77 ? "Kararımız: lansman Mart ayında." : "Rutin durum güncellemesi numara \(index).",
                speaker: index % 2 + 1)
    })
    transcript.speakerNames = [1: "Ayşe"]
    return transcript
}

@Suite struct SummarizerTests {
    let model = AIModel(provider: .claudeCode, id: "fake", displayName: "Fake")

    @Test func shortTranscriptIsSummarizedInOneRequest() async throws {
        let provider = FakeAIProvider(budget: 100_000) { _ in "## Özet\nKısa bir konuşma [0:00]." }
        let progress = ProgressLog()
        let summary = try await collect(Summarizer.summarize(transcript: longTranscript(lines: 4), provider: provider, model: model) { progress.append($0) })

        #expect(summary == "## Özet\nKısa bir konuşma [0:00].")
        #expect(provider.calls.count == 1)
        #expect(progress.values.isEmpty)
        let call = try #require(provider.calls.first)
        #expect(call.system.contains("Write in Turkish"))
        #expect(call.system.contains("Özet, Önemli noktalar"))
        #expect(call.system.contains("## Kim ne dedi")) // headings are localized in the template
        #expect(call.messages.count == 1)
        #expect(call.messages[0].role == .user)
        #expect(call.messages[0].text.contains("<transcript>\n[0:00] Ayşe: Rutin durum güncellemesi numara 0."))
        #expect(call.messages[0].text.contains("Speakers (in order of first appearance): Ayşe, Speaker 2"))
    }

    @Test func longTranscriptIsMapReduced() async throws {
        let transcript = longTranscript()
        let budget = 1_500
        let provider = FakeAIProvider(budget: budget) { call in
            if call.system.contains("take notes on one part") {
                let part = call.messages[0].text.contains("Kararımız") ? "- Lansman Mart [51:20]" : "- rutin"
                return part
            }
            return "## Özet\nLansman Mart ayında [51:20]."
        }
        let progress = ProgressLog()
        let summary = try await collect(Summarizer.summarize(transcript: transcript, provider: provider, model: model) { progress.append($0) })

        let chunkCount = TranscriptPromptBuilder.chunks(of: transcript, maxCharacters: budget).count
        #expect(chunkCount > 1)
        #expect(summary == "## Özet\nLansman Mart ayında [51:20].")
        #expect(provider.calls.count == chunkCount + 1)
        // Every map request stays within budget and says which part it is.
        for (index, call) in provider.calls.dropLast().enumerated() {
            #expect(call.messages[0].text.contains("<transcript_part number=\"\(index + 1)\" of=\"\(chunkCount)\">"))
        }
        let reduce = try #require(provider.calls.last)
        #expect(reduce.system.contains("notes taken on consecutive parts"))
        #expect(reduce.messages[0].text.contains("- Lansman Mart [51:20]"))
        #expect(reduce.messages[0].text.contains("<notes part=\"\(chunkCount)\">"))
        // Small budget → compact prompt.
        #expect(reduce.system.contains("You summarize recorded conversations."))
        #expect(progress.values.first == 0)
        #expect(progress.values.last == 1)
        #expect(progress.values == progress.values.sorted())
    }

    @Test func notesThatDoNotFitAreCondensed() async throws {
        let transcript = longTranscript()
        let budget = 1_500
        let provider = FakeAIProvider(budget: budget) { call in
            if call.system.contains("Merge them into one shorter set of notes") { return "- merged" }
            if call.system.contains("take notes on one part") { return String(repeating: "- long note line\n", count: 40) }
            return "Final"
        }
        let summary = try await collect(Summarizer.summarize(transcript: transcript, provider: provider, model: model))
        #expect(summary == "Final")
        let reduce = try #require(provider.calls.last)
        #expect(reduce.messages[0].text.contains("- merged"))
        #expect(!reduce.messages[0].text.contains("long note line"))
    }

    @Test func providerErrorsPropagate() async {
        let provider = FakeAIProvider(budget: 100_000) { _ in throw AIError("boom") }
        await #expect(throws: AIError("boom")) {
            _ = try await collect(Summarizer.summarize(transcript: longTranscript(lines: 3), provider: provider, model: model))
        }
    }

    @Test func emptyTranscriptFails() async {
        let provider = FakeAIProvider(budget: 100_000) { _ in "" }
        let empty = Fixtures.transcript(segments: [])
        await #expect(throws: AIError.self) {
            _ = try await collect(Summarizer.summarize(transcript: empty, provider: provider, model: model))
        }
        #expect(provider.calls.isEmpty)
    }

    @Test func noSpeakerSectionWithoutSpeakers() async throws {
        let provider = FakeAIProvider(budget: 100_000) { _ in "ok" }
        var transcript = Fixtures.transcript()
        transcript.language = "en"
        _ = try await collect(Summarizer.summarize(transcript: transcript, provider: provider, model: model))
        let system = try #require(provider.calls.first?.system)
        #expect(!system.contains("Who said what"))
        #expect(system.contains("Write in English"))
    }
}

@Suite struct AssistantTests {
    let model = AIModel(provider: .claudeCode, id: "fake", displayName: "Fake")

    @Test func smallTranscriptGoesWholeIntoSystemPrompt() async throws {
        let provider = FakeAIProvider(budget: 100_000) { _ in "Mart ayında [51:20]." }
        let history = [AIMessage(role: .user, text: "Merhaba"), AIMessage(role: .assistant, text: "Merhaba!")]
        let answer = try await collect(Assistant.answer(question: "Lansman ne zaman?", history: history, transcript: longTranscript(lines: 80), provider: provider, model: model))

        #expect(answer == "Mart ayında [51:20].")
        let call = try #require(provider.calls.first)
        #expect(call.system.contains("Below is the full transcript."))
        #expect(call.system.contains("[51:20] Speaker 2: Kararımız: lansman Mart ayında."))
        #expect(call.system.contains("Answer in the language of the user's question"))
        #expect(call.messages == history + [AIMessage(role: .user, text: "Lansman ne zaman?")])
    }

    @Test func largeTranscriptUsesRetrievedExcerpts() throws {
        let transcript = longTranscript()
        let request = try Assistant.makeRequest(question: "Lansman ne zaman?", history: [], transcript: transcript, budget: 2_000)
        #expect(request.isExcerpt)
        #expect(request.system.contains("Kararımız: lansman Mart ayında."))
        #expect(request.system.contains("Below are only the excerpts"))
        #expect(!request.system.contains(TranscriptPromptBuilder.render(transcript)))
        // Compact rules for small-context models.
        #expect(request.system.contains("Rules: answer only from the transcript"))
    }

    @Test func followUpsRetrieveUsingThePreviousQuestion() throws {
        let history = [AIMessage(role: .user, text: "Lansman ne zaman?"), AIMessage(role: .assistant, text: "Mart.")]
        let request = try Assistant.makeRequest(question: "Bundan kim sorumlu?", history: history, transcript: longTranscript(), budget: 2_000)
        #expect(request.system.contains("Kararımız: lansman Mart ayında."))
    }

    @Test func historyIsTrimmedToRecentCompleteTurns() {
        let history = [
            AIMessage(role: .user, text: String(repeating: "a", count: 500)),
            AIMessage(role: .assistant, text: "old answer"),
            AIMessage(role: .user, text: "recent question"),
            AIMessage(role: .assistant, text: "recent answer"),
            AIMessage(role: .user, text: "unanswered"),
        ]
        #expect(Assistant.recentHistory(history, maxCharacters: 100) == [
            AIMessage(role: .user, text: "recent question"),
            AIMessage(role: .assistant, text: "recent answer"),
        ])
    }

    @Test func emptyQuestionFails() {
        #expect(throws: AIError.self) {
            try Assistant.makeRequest(question: "  ", history: [], transcript: longTranscript(lines: 3), budget: 1_000)
        }
    }
}
