import Foundation
import Observation
import TranskribeCore

/// Runs summaries and questions against the model the user picked, streaming into drafts the
/// UI shows live, and saves finished results into the transcript.
@MainActor
@Observable
final class AIService {
    struct Draft: Equatable {
        var text = ""
        var progress: Double?
        var error: String?
    }

    private(set) var availability: [AIProviderKind: AIAvailability] = [:]
    var selectedModel: AIModel {
        didSet { saveSelection() }
    }
    private(set) var summaryDrafts: [Transcript.ID: Draft] = [:]
    private(set) var answerDrafts: [Transcript.ID: Draft] = [:]
    /// The conversation with the whole library (not saved).
    var libraryExchanges: [LibraryExchange] = []
    var libraryTask: Task<Void, Never>?

    let providers: [any AIProvider]
    private weak var model: AppModel?
    private var tasks: [String: Task<Void, Never>] = [:]
    private static let selectionKey = "aiModel"

    init(model: AppModel) {
        self.model = model
        providers = [ClaudeCodeProvider(), AppleIntelligenceProvider(), AnthropicAPIProvider()]
        let saved = UserDefaults.standard.data(forKey: Self.selectionKey).flatMap { try? JSONDecoder().decode(AIModel.self, from: $0) }
        selectedModel = saved ?? ClaudeCodeProvider.sonnet
        Task { await refreshAvailability() }
    }

    var allModels: [AIModel] { providers.flatMap(\.models) }

    func provider(for model: AIModel) -> (any AIProvider)? {
        providers.first { $0.kind == model.provider }
    }

    func isAvailable(_ model: AIModel) -> Bool {
        availability[model.provider]?.isAvailable ?? false
    }

    func refreshAvailability() async {
        for provider in providers {
            availability[provider.kind] = await provider.availability()
        }
        // Prefer a model that actually works over a remembered one that doesn't.
        if !isAvailable(selectedModel), let working = allModels.first(where: isAvailable) {
            selectedModel = working
        }
    }

    var isSummarizing: (Transcript.ID) -> Bool {
        { [summaryDrafts] id in summaryDrafts[id] != nil && summaryDrafts[id]?.error == nil }
    }

    // MARK: - Summary

    func summarize(_ transcript: Transcript) {
        guard let provider = provider(for: selectedModel) else { return }
        let id = transcript.id
        let chosen = selectedModel
        cancel(key: "summary-\(id)")
        summaryDrafts[id] = Draft(progress: 0)
        tasks["summary-\(id)"] = Task {
            do {
                let stream = Summarizer.summarize(transcript: transcript, provider: provider, model: chosen) { [weak self] value in
                    Task { @MainActor in self?.summaryDrafts[id]?.progress = value }
                }
                for try await delta in stream {
                    summaryDrafts[id, default: Draft()].text += delta
                    summaryDrafts[id]?.progress = nil
                }
                let markdown = summaryDrafts[id]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !markdown.isEmpty else { throw AIError("The model returned an empty summary.") }
                model?.update(id, persist: true) {
                    $0.summary = AISummary(markdown: markdown, modelName: chosen.displayName)
                }
                summaryDrafts[id] = nil
            } catch is CancellationError {
                summaryDrafts[id] = nil
            } catch {
                summaryDrafts[id, default: Draft()].error = error.localizedDescription
            }
        }
    }

    func cancelSummary(_ id: Transcript.ID) {
        cancel(key: "summary-\(id)")
        summaryDrafts[id] = nil
    }

    // MARK: - Questions

    func ask(_ question: String, about transcript: Transcript) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let provider = provider(for: selectedModel) else { return }
        let id = transcript.id
        let chosen = selectedModel
        let history = transcript.chat?.messages ?? []
        model?.update(id, persist: true) {
            var chat = $0.chat ?? AIChat()
            chat.messages.append(AIMessage(role: .user, text: trimmed))
            chat.modelName = chosen.displayName
            $0.chat = chat
        }
        cancel(key: "answer-\(id)")
        answerDrafts[id] = Draft()
        tasks["answer-\(id)"] = Task {
            do {
                let stream = Assistant.answer(question: trimmed, history: history, transcript: transcript,
                                              provider: provider, model: chosen)
                for try await delta in stream {
                    answerDrafts[id, default: Draft()].text += delta
                }
                let answer = answerDrafts[id]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                model?.update(id, persist: true) {
                    $0.chat?.messages.append(AIMessage(role: .assistant, text: answer.isEmpty ? "(No answer)" : answer))
                }
                answerDrafts[id] = nil
            } catch is CancellationError {
                answerDrafts[id] = nil
            } catch {
                answerDrafts[id, default: Draft()].error = error.localizedDescription
            }
        }
    }

    func cancelAnswer(_ id: Transcript.ID) {
        cancel(key: "answer-\(id)")
        answerDrafts[id] = nil
    }

    func clearChat(_ id: Transcript.ID) {
        cancelAnswer(id)
        model?.update(id, persist: true) { $0.chat = nil }
    }

    // MARK: - Helpers

    private func cancel(key: String) {
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selectedModel) {
            UserDefaults.standard.set(data, forKey: Self.selectionKey)
        }
    }
}
