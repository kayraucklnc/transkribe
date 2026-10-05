import Foundation

/// Summarizes a transcript with any provider. Transcripts that fit the model's budget go in one
/// request; longer ones are map-reduced: notes per chunk, then one summary from the notes.
public enum Summarizer {
    /// Below this budget a model gets the compact prompts (small on-device context).
    static let compactBudgetThreshold = 20_000
    /// How many times notes may be condensed further when they still don't fit.
    static let maxCondenseRounds = 3

    /// Streams the final summary's text deltas. During map-reduce nothing is yielded until the
    /// final step starts; `progress` reports 0…1 meanwhile (it reaches 1 as the final step begins).
    /// Single-request summaries don't report progress.
    public static func summarize(
        transcript: Transcript,
        provider: any AIProvider,
        model: AIModel,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AIStreaming.run { yield in
            try await summarize(transcript: transcript, provider: provider, model: model, progress: progress, yield: yield)
        }
    }

    private static func summarize(
        transcript: Transcript,
        provider: any AIProvider,
        model: AIModel,
        progress: (@Sendable (Double) -> Void)?,
        yield: @Sendable (String) -> Void
    ) async throws {
        let lines = TranscriptPromptBuilder.lines(of: transcript)
        guard !lines.isEmpty else { throw AIError("This transcript has no text to summarize.") }
        let budget = provider.contextCharacterBudget(for: model)
        let compact = budget < compactBudgetThreshold
        let rendered = lines.joined(separator: "\n")

        if rendered.count <= budget {
            let system = Prompts.summarySystem(for: transcript, compact: compact)
            let user = Prompts.summaryUser(transcript: transcript, rendered: rendered)
            try await AIStreaming.forward(provider.stream(model: model, system: system, messages: [AIMessage(role: .user, text: user)]), to: yield)
            return
        }

        let chunks = TranscriptPromptBuilder.chunks(lines: lines, maxCharacters: budget)
        progress?(0)
        var notes: [String] = []
        let notesSystem = Prompts.partialNotesSystem(for: transcript)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let user = Prompts.partialNotesUser(transcript: transcript, chunk: chunk, part: index + 1, of: chunks.count)
            let note = try await AIStreaming.collect(provider.stream(model: model, system: notesSystem, messages: [AIMessage(role: .user, text: user)]))
            if !note.isEmpty { notes.append(note) }
            progress?(Double(index + 1) / Double(chunks.count + 1))
        }
        guard !notes.isEmpty else { throw AIError("The model returned no notes for this transcript.") }

        notes = try await condense(notes, budget: budget, transcript: transcript, provider: provider, model: model)
        progress?(1)

        let system = Prompts.summarySystem(for: transcript, compact: compact, fromNotes: true)
        let user = Prompts.notesUser(transcript: transcript, notes: notes, instruction: Prompts.reduceInstruction)
        try await AIStreaming.forward(provider.stream(model: model, system: system, messages: [AIMessage(role: .user, text: user)]), to: yield)
    }

    /// Merges groups of notes until they fit in the budget (or the round limit is hit).
    private static func condense(
        _ notes: [String],
        budget: Int,
        transcript: Transcript,
        provider: any AIProvider,
        model: AIModel
    ) async throws -> [String] {
        var notes = notes
        var round = 0
        let system = Prompts.condenseNotesSystem(for: transcript)
        while notes.joined(separator: "\n\n").count > budget, round < maxCondenseRounds {
            round += 1
            let groups = TranscriptPromptBuilder.chunks(lines: notes, maxCharacters: budget)
            var condensed: [String] = []
            for group in groups {
                try Task.checkCancellation()
                let user = Prompts.notesUser(transcript: transcript, notes: [group], instruction: Prompts.condenseInstruction)
                let note = try await AIStreaming.collect(provider.stream(model: model, system: system, messages: [AIMessage(role: .user, text: user)]))
                if !note.isEmpty { condensed.append(note) }
            }
            guard !condensed.isEmpty else { break }
            notes = condensed
        }
        return notes
    }
}

/// Small helpers shared by the orchestrators and providers.
enum AIStreaming {
    /// Runs `body` in a task feeding a stream; cancelling the consumer cancels the task.
    static func run(_ body: @escaping @Sendable (_ yield: @escaping @Sendable (String) -> Void) async throws -> Void) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await body { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func forward(_ stream: AsyncThrowingStream<String, Error>, to yield: @Sendable (String) -> Void) async throws {
        for try await delta in stream { yield(delta) }
        try Task.checkCancellation()
    }

    static func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var text = ""
        for try await delta in stream { text += delta }
        try Task.checkCancellation()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
