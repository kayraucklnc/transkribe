import SwiftUI
import TranskribeCore

/// Home: three ways to start, a question box, the people you talk with, and every conversation.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var isSearching = false
    @State private var isAsking = false
    @State private var askQuestion = ""

    var body: some View {
        @Bindable var model = model
        let isQuerying = !model.query.trimmingCharacters(in: .whitespaces).isEmpty
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Header()
                if isQuerying {
                    let results = model.filteredTranscripts
                    if results.isEmpty {
                        ContentUnavailableView.search(text: model.query)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        SearchResults(transcripts: results, query: model.query)
                    }
                } else {
                    HomeActions()
                    if !model.transcripts.isEmpty {
                        LibraryAskBar(isPresented: $isAsking, question: $askQuestion)
                    }
                    if !model.people.isEmpty {
                        PeopleStrip()
                    }
                    if model.transcripts.isEmpty {
                        EmptyLibrary()
                    } else {
                        ForEach(DateSection.group(model.transcripts), id: \.title) { section in
                            ConversationGroup(title: section.title, transcripts: section.transcripts)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 60)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Surface.window)
        .searchable(text: $model.query, isPresented: $isSearching, placement: .toolbar, prompt: "Search Conversations")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { FileImport.presentOpenPanel(model: model) } label: {
                    Label("Transcribe a File", systemImage: "square.and.arrow.down")
                }
                .help("Transcribe an audio or video file (⌘O)")
            }
        }
        .sheet(isPresented: $isAsking) {
            LibraryChatView(question: $askQuestion)
        }
        .background {
            Button("") { isSearching = true }
                .keyboardShortcut("f")
                .hidden()
        }
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Surface.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
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
