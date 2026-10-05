import Foundation

/// Answers questions about a transcript. The transcript goes in the system prompt (whole when it
/// fits, otherwise the excerpts most relevant to the question), the chat history in the messages.
public enum Assistant {
    /// Share of the budget the chat history may use before older turns are dropped.
    static let historyShare = 0.25

    public static func answer(
        question: String,
        history: [AIMessage],
        transcript: Transcript,
        provider: any AIProvider,
        model: AIModel
    ) -> AsyncThrowingStream<String, Error> {
        AIStreaming.run { yield in
            let request = try makeRequest(
                question: question,
                history: history,
                transcript: transcript,
                budget: provider.contextCharacterBudget(for: model)
            )
            try await AIStreaming.forward(provider.stream(model: model, system: request.system, messages: request.messages), to: yield)
        }
    }

    struct Request: Equatable {
        var system: String
        var messages: [AIMessage]
        var isExcerpt: Bool
    }

    static func makeRequest(question: String, history: [AIMessage], transcript: Transcript, budget: Int) throws -> Request {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw AIError("Ask a question about the transcript.") }
        let lines = TranscriptPromptBuilder.lines(of: transcript)
        guard !lines.isEmpty else { throw AIError("This transcript has no text to ask about.") }

        let history = recentHistory(history, maxCharacters: Int(Double(budget) * historyShare))
        let used = history.reduce(question.count) { $0 + $1.text.count }
        let transcriptBudget = max(budget - used, budget / 2)
        let rendered = lines.joined(separator: "\n")
        let isExcerpt = rendered.count > transcriptBudget
        let context: String
        if isExcerpt {
            // Include the previous question so follow-ups ("and who agreed?") keep their topic.
            let previous = history.last { $0.role == .user }?.text ?? ""
            context = TranscriptRetriever.excerpts(for: question + "\n" + previous, in: transcript, budget: transcriptBudget)
        } else {
            context = rendered
        }
        let system = Prompts.questionSystem(
            for: transcript,
            context: context,
            isExcerpt: isExcerpt,
            compact: budget < Summarizer.compactBudgetThreshold
        )
        return Request(system: system, messages: history + [AIMessage(role: .user, text: question)], isExcerpt: isExcerpt)
    }

    /// The most recent complete turns that fit, starting with a user message and alternating roles.
    static func recentHistory(_ history: [AIMessage], maxCharacters: Int) -> [AIMessage] {
        let cleaned = history.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var kept: [AIMessage] = []
        var total = 0
        for message in cleaned.reversed() {
            guard total + message.text.count <= maxCharacters else { break }
            total += message.text.count
            kept.insert(message, at: 0)
        }
        // The next message is the user's question, so history must end with the assistant
        // and start with the user.
        while let last = kept.last, last.role == .user { kept.removeLast() }
        while let first = kept.first, first.role == .assistant { kept.removeFirst() }
        return kept
    }
}
