import SwiftUI
import TranskribeCore

/// Home: a stage with one obvious thing to do (record), then everything you've captured.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var isSearching = false
    @State private var isAsking = false
    @State private var askQuestion = ""
    @State private var meaning: MeaningState = .off
    @Environment(AIService.self) private var ai

    enum MeaningState: Equatable {
        case off, searching, found([String]), failed(String)
    }

    var body: some View {
        @Bindable var model = model
        let isQuerying = !model.query.trimmingCharacters(in: .whitespaces).isEmpty
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isQuerying {
                    Header()
                        .padding(.bottom, 24)
                    MeaningBar(state: meaning) { searchByMeaning() }
                        .padding(.bottom, 16)
                    if case .found(let terms) = meaning {
                        let results = MeaningSearch.rank(model.transcripts, terms: terms)
                        if results.isEmpty {
                            ContentUnavailableView.search(text: model.query).frame(maxWidth: .infinity).padding(.top, 30)
                        } else {
                            SearchResults(transcripts: results, query: model.query, terms: terms)
                        }
                    } else {
                        let results = model.filteredTranscripts
                        if results.isEmpty {
                            ContentUnavailableView.search(text: model.query)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else {
                            SearchResults(transcripts: results, query: model.query)
                        }
                    }
                } else {
                    Hero()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    if !model.transcripts.isEmpty {
                        AskBar(isPresented: $isAsking)
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        SectionTitle("Recent")
                            .padding(.top, 54)
                        RecentCards(transcripts: Array(model.transcripts.prefix(8)))
                    } else {
                        EmptyLibrary()
                            .padding(.top, 50)
                    }
                    if !model.people.isEmpty {
                        SectionTitle("People")
                            .padding(.top, 34)
                        PeopleStrip()
                            .padding(.top, 14)
                    }
                    if model.transcripts.count > 1 {
                        SectionTitle("All Conversations")
                            .padding(.top, 40)
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(DateSection.group(model.transcripts), id: \.title) { section in
                                ConversationGroup(title: section.title, transcripts: section.transcripts)
                            }
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 20)
            .padding(.bottom, 70)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(StageBackdrop())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .searchable(text: $model.query, isPresented: $isSearching, placement: .toolbar, prompt: "Search Conversations")
        .sheet(isPresented: $isAsking) {
            LibraryChatView(question: $askQuestion)
        }
        .onChange(of: model.query) { _, _ in meaning = .off }
        .background {
            Button("") { isSearching = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }
}

extension LibraryView {
    private func searchByMeaning() {
        let query = model.query.trimmingCharacters(in: .whitespaces)
        meaning = .searching
        Task {
            do {
                let terms = try await ai.expandSearch(query, languages: model.settings.languages)
                if model.query.trimmingCharacters(in: .whitespaces) == query { meaning = .found(terms) }
            } catch {
                meaning = .failed(error.localizedDescription)
            }
        }
    }
}

/// "Search by meaning" and, once used, the words it searched for.
private struct MeaningBar: View {
    let state: LibraryView.MeaningState
    let search: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .off:
                Button(action: search) { Label("Search by meaning", systemImage: "sparkle.magnifyingglass") }
                    .buttonStyle(.bordered)
                Text("Also finds related words and translations, like “fiyat” for “price”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .searching:
                ProgressView().controlSize(.small)
                Text("Thinking of related words…").font(.callout).foregroundStyle(.secondary)
            case .found(let terms):
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.record)
                FlowLayout(spacing: 6) {
                    ForEach(terms, id: \.self) { term in
                        Text(term)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                Button("Try Again", action: search).buttonStyle(.borderless)
            }
        }
        .animation(Theme.spring, value: state)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold))
            .tracking(-0.4)
    }
}

/// "Conversations" with a one-line account of the week.
private struct Header: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Conversations")
                .font(.system(size: 26, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let count = model.transcripts.count
        guard count > 0 else { return "Record, import or dictate. Everything stays on this Mac." }
        let week = model.transcripts.filter { $0.createdAt > Date().addingTimeInterval(-7 * 86_400) }
        let total = "\(count) conversation\(count == 1 ? "" : "s")"
        guard !week.isEmpty else { return total }
        let length = Duration.seconds(week.reduce(0) { $0 + $1.duration })
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(total) · \(length) this week"
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No conversations yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Record a call or meeting, or drop an audio or video file onto this window. Each one becomes a chat you can play back, search and ask about.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Stage.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

/// Groups transcripts by recency: Today, Yesterday, Previous 7 Days, then by month.
struct DateSection {
    let title: String
    var transcripts: [Transcript]

    static func group(_ transcripts: [Transcript], now: Date = Date(), calendar: Calendar = .current) -> [DateSection] {
        var sections: [DateSection] = []
        for transcript in transcripts {
            let title = sectionTitle(for: transcript.createdAt, now: now, calendar: calendar)
            if sections.last?.title == title {
                sections[sections.count - 1].transcripts.append(transcript)
            } else {
                sections.append(DateSection(title: title, transcripts: [transcript]))
            }
        }
        return sections
    }

    private static func sectionTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "Previous 7 Days" }
        if days < 30 { return "Previous 30 Days" }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
