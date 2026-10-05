import SwiftUI
import TranskribeCore

/// Summary and questions about the open conversation, using the model the user picked.
struct InsightsPanel: View {
    let transcript: Transcript
    @AppStorage("insightsTab") private var tab = Tab.summary
    @Namespace private var tabSelection

    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case todos = "To-dos"
        case ask = "Ask"

        var symbol: String {
            switch self {
            case .summary: "sparkles"
            case .todos: "checklist"
            case .ask: "bubble.left.and.text.bubble.right"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(Tab.allCases, id: \.self) { item in
                        Button {
                            withAnimation(Theme.spring) { tab = item }
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.callout.weight(tab == item ? .semibold : .medium))
                                .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background {
                                    if tab == item {
                                        Capsule()
                                            .fill(Theme.card)
                                            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                                            .matchedGeometryEffect(id: "tab", in: tabSelection)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.primary.opacity(0.06), in: Capsule())
                Spacer()
                ModelPicker()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Group {
                switch tab {
                case .summary: SummaryTab(transcript: transcript)
                case .todos: ActionItemsTab(transcript: transcript)
                case .ask: AskTab(transcript: transcript)
                }
            }
            .transition(.opacity)
        }
        .frame(maxHeight: .infinity)
        .background {
            ZStack(alignment: .top) {
                Theme.canvas
                LinearGradient(colors: [Color.accentColor.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
            }
        }
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
            HStack(spacing: 5) {
                Image(systemName: Self.symbol(for: ai.selectedModel.provider))
                Text(Self.shortName(ai.selectedModel))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
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

// MARK: - Summary

/// A summary split into its sections, each shown as a card.
struct SummarySections {
    struct Section: Identifiable {
        let id: Int
        let title: String
        let body: String
    }

    let sections: [Section]

    init(markdown: String) {
        var result: [Section] = []
        var title = ""
        var lines: [String] = []
        func flush() {
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty || !title.isEmpty { result.append(Section(id: result.count, title: title, body: body)) }
            lines = []
        }
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") || line.hasPrefix("# ") {
                flush()
                title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            } else {
                lines.append(line)
            }
        }
        flush()
        sections = result
    }

    /// Icons by position in the summary template (headings are localized, positions are not).
    static func symbol(for title: String, index: Int) -> String {
        let lower = title.lowercased()
        if lower.contains("action") || lower.contains("yapılacak") || lower.contains("aufgab") { return "checklist" }
        if lower.contains("decision") || lower.contains("karar") || lower.contains("entscheid") { return "checkmark.seal" }
        if lower.contains("question") || lower.contains("soru") || lower.contains("frage") { return "questionmark.bubble" }
        if lower.contains("who") || lower.contains("kim") || lower.contains("wer") { return "person.2" }
        if lower.contains("key") || lower.contains("önemli") || lower.contains("wichtig") { return "list.bullet.rectangle" }
        return index == 0 ? "text.quote" : "doc.text"
    }
}

private struct SummaryTab: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai

    var body: some View {
        let draft = ai.summaryDrafts[transcript.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let draft {
                    if let error = draft.error {
                        ErrorCard(message: error) { ai.summarize(transcript) }
                    } else if draft.text.isEmpty {
                        Working(title: "Reading the conversation…", progress: draft.progress) { ai.cancelSummary(transcript.id) }
                    } else {
                        SectionCards(markdown: draft.text)
                        Working(title: "Writing…", progress: nil) { ai.cancelSummary(transcript.id) }
                    }
                } else if let summary = transcript.summary {
                    SectionCards(markdown: summary.markdown)
                    HStack(spacing: 12) {
                        Text("\(ModelPicker.shortName(AIModel(provider: .claudeCode, id: "", displayName: summary.modelName))) · \(summary.createdAt.formatted(.relative(presentation: .named)))")
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
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                } else {
                    SummarizeHero(transcript: transcript)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SectionCards: View {
    let markdown: String

    var body: some View {
        let sections = SummarySections(markdown: markdown).sections
        ForEach(sections) { section in
            if section.id == 0 {
                // The gist, set apart so it's the first thing you read.
                VStack(alignment: .leading, spacing: 8) {
                    Label(section.title.isEmpty ? "Summary" : section.title, systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.tint)
                    MarkdownView(markdown: section.body, fontSize: 14.5)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.accentColor.opacity(0.2)))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(section.title, systemImage: SummarySections.symbol(for: section.title, index: section.id))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MarkdownView(markdown: section.body, fontSize: 13.5)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06)))
            }
        }
    }
}

private struct SummarizeHero: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai
    @State private var glow = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: 90, height: 90)
                    .blur(radius: 24)
                    .scaleEffect(glow ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glow)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.top, 36)
            .onAppear { glow = true }
            Text("Summarize this conversation")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("The gist, decisions, who does what next, and what's still open.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button {
                ai.summarize(transcript)
            } label: {
                Label("Summarize", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .background(Theme.myBubble, in: Capsule())
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(transcript.status != .done || transcript.segments.isEmpty || !ai.isAvailable(ai.selectedModel))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ask

private struct AskTab: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        let messages = transcript.chat?.messages ?? []
        let draft = ai.answerDrafts[transcript.id]
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty, draft == nil {
                            Suggestions(transcript: transcript) { send($0) }
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            ChatMessageView(message: message)
                        }
                        if let draft {
                            if let error = draft.error {
                                ErrorCard(message: error) { ai.cancelAnswer(transcript.id) }
                            } else if draft.text.isEmpty {
                                AssistantBubble { ThinkingDots() }
                            } else {
                                AssistantBubble { MarkdownView(markdown: draft.text) }
                            }
                        }
                        Color.clear.frame(height: 80).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: draft?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            Composer(question: $question, focused: $focused, isAnswering: draft != nil && draft?.error == nil,
                     onSend: { send(question) }, onStop: { ai.cancelAnswer(transcript.id) })
                .padding(12)
        }
        .contextMenu {
            Button("Clear Conversation") { ai.clearChat(transcript.id) }
                .disabled(messages.isEmpty)
        }
    }

    private func send(_ text: String) {
        guard transcript.status == .done, ai.isAvailable(ai.selectedModel),
              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        ai.ask(text, about: transcript)
        question = ""
    }
}

private struct ChatMessageView: View {
    let message: AIMessage

    var body: some View {
        if message.role == .user {
            Text(message.text)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.myBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        } else {
            AssistantBubble { MarkdownView(markdown: message.text) }
        }
    }
}

struct AssistantBubble<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.07), in: Circle())
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06)))
        }
        .padding(.trailing, 24)
    }
}

struct ThinkingDots: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .phaseAnimator([0.3, 1.0]) { view, opacity in view.opacity(opacity) } animation: { _ in
                        .easeInOut(duration: 0.6).delay(Double(index) * 0.2)
                    }
            }
        }
        .padding(.vertical, 4)
    }
}

struct Composer: View {
    @Binding var question: String
    var focused: FocusState<Bool>.Binding
    let isAnswering: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    var placeholder = "Ask about this conversation…"

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused(focused)
                .onSubmit(onSend)
                .padding(.vertical, 6)
            if isAnswering {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(question.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.4)) : AnyShapeStyle(Theme.myBubble), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct Suggestions: View {
    let transcript: Transcript
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask anything about this conversation")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .padding(.top, 16)
            Text("Facts come from what was said. Ask for feedback and advice too.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            ForEach(suggestions, id: \.self) { suggestion in
                Button { onPick(suggestion) } label: {
                    HStack {
                        Text(suggestion).font(.callout).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var suggestions: [String] {
        var list: [String]
        let wants: (String) -> String
        switch transcript.language {
        case "tr":
            list = ["Nasıl geçti, ben nasıldım?", "Karşı taraf ikna oldu mu?", "Başka ne söyleyebilirdim?", "Kim neyi yapacak?"]
            wants = { "\($0) gerçekten ne istiyor?" }
        case "it":
            list = ["Com'è andata, come sono stato?", "Erano convinti?", "Cos'altro avrei potuto dire?", "Chi fa cosa adesso?"]
            wants = { "Cosa vuole davvero \($0)?" }
        default:
            list = ["How did I do?", "Were they convinced?", "What else could I have said?", "Who is doing what next?"]
            wants = { "What does \($0) really want?" }
        }
        if transcript.hasSpeakers, let other = transcript.speakers.first(where: { $0 != transcript.resolvedMeSpeaker }) {
            list.append(wants(transcript.name(of: other)))
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
        .padding(.vertical, 6)
    }
}

struct ErrorCard: View {
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
