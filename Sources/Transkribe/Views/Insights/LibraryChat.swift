import SwiftUI
import TranskribeCore

/// The glass bar on Home: ask anything across every conversation.
struct LibraryAskBar: View {
    @Binding var isPresented: Bool
    @Binding var question: String
    @State private var isHovering = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [.purple, .accentColor], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                Text("Ask about all your conversations…")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘K")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
            .glassBackground(in: Capsule(), interactive: true)
            .scaleEffect(isHovering ? 1.01 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Theme.spring) { isHovering = hovering } }
        .keyboardShortcut("k")
        .help("Ask questions that span every conversation, like “What did Hakan say about the price?”")
    }
}

/// A chat with the whole library. The model searches and reads conversations itself;
/// each lookup shows up as a small chip so it's clear where an answer comes from.
struct LibraryChatView: View {
    var focus: Person?
    @Binding var question: String
    @Environment(AIService.self) private var ai
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        let exchanges = ai.libraryExchanges
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if exchanges.isEmpty {
                                LibrarySuggestions(focus: focus, language: model.transcripts.first?.language) { send($0) }
                            }
                            ForEach(exchanges) { exchange in
                                ExchangeView(exchange: exchange) { dismiss() }
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            Color.clear.frame(height: 80).id("bottom")
                        }
                        .padding(20)
                    }
                    .onChange(of: exchanges.last?.answer) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: exchanges.last?.steps.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                Composer(question: $question, focused: $focused, isAnswering: exchanges.last?.isRunning == true,
                         onSend: { send(question) }, onStop: { ai.libraryTask?.cancel() },
                         placeholder: focus.map { "Ask about \($0.name)…" } ?? "Ask about your conversations…")
                    .padding(14)
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 720)
        .background(AmbientBackground())
        .onAppear {
            focused = true
            if !question.trimmingCharacters(in: .whitespaces).isEmpty { send(question) }
        }
        .animation(Theme.spring, value: exchanges.count)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let focus {
                PersonAvatar(initials: focus.initials, seed: focus.name, size: 26)
                Text(focus.name).font(.headline)
            } else {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text("All conversations").font(.headline)
            }
            Spacer()
            ModelPicker()
            if !ai.libraryExchanges.isEmpty {
                Button { withAnimation(Theme.spring) { ai.clearLibraryChat() } } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("New chat")
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func send(_ text: String) {
        guard ai.isAvailable(ai.selectedModel), ai.libraryExchanges.last?.isRunning != true,
              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        ai.askLibrary(text, focus: focus, transcripts: model.transcripts, people: model.people,
                      userName: NSFullUserName().isEmpty ? nil : NSFullUserName())
        question = ""
    }
}

private struct ExchangeView: View {
    let exchange: LibraryExchange
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exchange.question)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.myBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 60)
            if !exchange.steps.isEmpty {
                StepChips(steps: exchange.steps, isRunning: exchange.isRunning && exchange.answer.isEmpty)
                    .padding(.leading, 32)
            }
            if let error = exchange.error {
                ErrorCard(message: error) {}
            } else if exchange.answer.isEmpty {
                if exchange.isRunning { AssistantBubble { ThinkingDots() } }
            } else {
                AssistantBubble { MarkdownView(markdown: exchange.answer, onOpen: onOpen) }
            }
        }
    }
}

/// "Searched “fiyat”" · "Read “Hakan bey” 2:10–10:00" — what the model looked at.
private struct StepChips: View {
    let steps: [String]
    let isRunning: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 5) {
                    Image(systemName: step.hasPrefix("Searched") ? "magnifyingglass" : step.hasPrefix("Read") ? "text.bubble" : "person.2")
                        .font(.system(size: 9, weight: .bold))
                    Text(step).lineLimit(1)
                    if isRunning, index == steps.count - 1 {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05), in: Capsule())
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: steps.count)
    }
}

private struct LibrarySuggestions: View {
    let focus: Person?
    let language: String?
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(focus.map { "Ask anything about \($0.name)" } ?? "Ask across every conversation")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .padding(.top, 12)
            Text("It searches and reads only the parts it needs, and links back to the moment.")
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
        let name = focus?.name
        switch (language, name) {
        case ("tr", let name?): return ["\(name) ile neler konuştuk?", "\(name) bana ne söz verdi?", "\(name) ile ilişkim nasıl gidiyor?"]
        case ("tr", nil): return ["Bu hafta neler konuştum?", "Kime ne söz verdim?", "Fiyat en son ne konuşuldu?"]
        case ("it", let name?): return ["Di cosa abbiamo parlato con \(name)?", "Cosa mi ha promesso \(name)?", "Come va il rapporto con \(name)?"]
        case ("it", nil): return ["Di cosa ho parlato questa settimana?", "Cosa ho promesso e a chi?", "Quando si è parlato del prezzo?"]
        case (_, let name?): return ["What have \(name) and I talked about?", "What did \(name) promise me?", "How is it going with \(name)?"]
        default: return ["What did I talk about this week?", "What did I promise, and to whom?", "When did we last discuss pricing?"]
        }
    }
}
