import SwiftUI
import TranskribeCore

/// Summary and questions about the open conversation, using the model the user picked.
struct InsightsPanel: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai
    @AppStorage("insightsTab") private var tab = Tab.summary

    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case ask = "Ask"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                Spacer()
                ModelPicker()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().opacity(0.5)
            switch tab {
            case .summary: SummaryTab(transcript: transcript)
            case .ask: AskTab(transcript: transcript)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.background)
        .overlay(alignment: .leading) { Divider() }
    }
}

/// Which model answers: Claude through the user's Claude Code login, Apple's on-device model,
/// or Claude through an API key.
struct ModelPicker: View {
    @Environment(AIService.self) private var ai
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            ForEach(ai.providers.map(\.kind), id: \.self) { kind in
                Section(Self.title(for: kind)) {
                    ForEach(ai.allModels.filter { $0.provider == kind }) { model in
                        Button {
                            ai.selectedModel = model
                        } label: {
                            if model == ai.selectedModel {
                                Label(model.displayName, systemImage: "checkmark")
                            } else {
                                Text(model.displayName)
                            }
                        }
                        .disabled(!ai.isAvailable(model))
                    }
                    if case .unavailable(let reason)? = ai.availability[kind] {
                        Text(reason)
                    }
                }
            }
            Divider()
            Button("AI Settings…") { openSettings() }
        } label: {
            Label(Self.shortName(ai.selectedModel), systemImage: Self.symbol(for: ai.selectedModel.provider))
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Choose the AI model")
        .task { await ai.refreshAvailability() }
    }

    /// "Claude Sonnet (Claude Code)" → "Sonnet": the icon already says where it runs.
    static func shortName(_ model: AIModel) -> String {
        switch model.provider {
        case .appleIntelligence: "On-device"
        case .claudeCode, .anthropicAPI:
            model.displayName
                .replacingOccurrences(of: " (Claude Code)", with: "")
                .replacingOccurrences(of: "Claude ", with: "")
        }
    }

    static func title(for kind: AIProviderKind) -> String {
        switch kind {
        case .claudeCode: "Claude · your Claude Code login"
        case .appleIntelligence: "On this Mac · private"
        case .anthropicAPI: "Claude · API key"
        }
    }

    static func symbol(for kind: AIProviderKind) -> String {
        switch kind {
        case .claudeCode: "terminal"
        case .appleIntelligence: "apple.intelligence"
        case .anthropicAPI: "key"
        }
    }
}

private struct SummaryTab: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai

    var body: some View {
        let draft = ai.summaryDrafts[transcript.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let draft {
                    if let error = draft.error {
                        ErrorCard(message: error) { ai.summarize(transcript) }
                    } else if draft.text.isEmpty {
                        Working(title: "Reading the conversation…", progress: draft.progress) { ai.cancelSummary(transcript.id) }
                    } else {
                        MarkdownView(markdown: draft.text)
                        Working(title: "Writing…", progress: nil) { ai.cancelSummary(transcript.id) }
                    }
                } else if let summary = transcript.summary {
                    MarkdownView(markdown: summary.markdown)
                    HStack(spacing: 12) {
                        Text("\(summary.modelName) · \(summary.createdAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(summary.markdown, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy summary")
                        Button { ai.summarize(transcript) } label: { Image(systemName: "arrow.clockwise") }
                            .help("Summarize again")
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 8)
                } else {
                    SummarizeHero(transcript: transcript)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SummarizeHero: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 30)
            Text("Summarize this conversation")
                .font(.headline)
            Text("Key points, decisions, action items with owners, open questions and who said what, with links to each moment.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                ai.summarize(transcript)
            } label: {
                Label("Summarize", systemImage: "sparkles")
                    .frame(maxWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(transcript.status != .done || transcript.segments.isEmpty || !ai.isAvailable(ai.selectedModel))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AskTab: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        let messages = transcript.chat?.messages ?? []
        let draft = ai.answerDrafts[transcript.id]
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            Suggestions(transcript: transcript) { send($0) }
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            if message.role == .user {
                                Text(message.text)
                                    .font(.callout)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.myBubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .textSelection(.enabled)
                            } else {
                                MarkdownView(markdown: message.text)
                            }
                        }
                        if let draft {
                            if let error = draft.error {
                                ErrorCard(message: error) { ai.cancelAnswer(transcript.id) }
                            } else if draft.text.isEmpty {
                                TypingIndicator().padding(.leading, -36)
                            } else {
                                MarkdownView(markdown: draft.text)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(18)
                }
                .onChange(of: draft?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            HStack(spacing: 8) {
                TextField("Ask about this conversation…", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onSubmit { send(question) }
                if draft != nil && draft?.error == nil {
                    Button { ai.cancelAnswer(transcript.id) } label: {
                        Image(systemName: "stop.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                } else {
                    Button { send(question) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(question.isEmpty ? Color.secondary : Color.accentColor)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.1)))
            .padding(12)
        }
        .contextMenu {
            Button("Clear Conversation") { ai.clearChat(transcript.id) }
                .disabled(messages.isEmpty)
        }
    }

    private func send(_ text: String) {
        guard transcript.status == .done, ai.isAvailable(ai.selectedModel) else { return }
        ai.ask(text, about: transcript)
        question = ""
    }
}

private struct Suggestions: View {
    let transcript: Transcript
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask anything about this conversation")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(suggestions, id: \.self) { suggestion in
                Button { onPick(suggestion) } label: {
                    Text(suggestion)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var suggestions: [String] {
        let turkish = transcript.language == "tr"
        var list = turkish
            ? ["Hangi kararlar alındı?", "Yapılacaklar ve sorumluları neler?", "Açık kalan sorular neler?"]
            : ["What was decided?", "List the action items and owners", "What questions are still open?"]
        if transcript.hasSpeakers, let other = transcript.speakers.first(where: { $0 != transcript.resolvedMeSpeaker }) {
            let name = transcript.name(of: other)
            list.append(turkish ? "\(name) ne istiyor?" : "What does \(name) want?")
        }
        return list
    }
}

private struct Working: View {
    let title: String
    let progress: Double?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(title).font(.callout).foregroundStyle(.secondary)
            if let progress, progress > 0 {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Stop", action: onCancel).buttonStyle(.borderless)
        }
    }
}

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Button("Try Again", action: onRetry)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
