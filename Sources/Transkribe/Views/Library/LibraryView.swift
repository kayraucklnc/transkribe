import SwiftUI
import TranskribeCore

/// Home: a warm welcome, one obvious way to start, and every conversation at a glance.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool
    @State private var isAsking = false
    @State private var askQuestion = ""

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Welcome()
                if !model.transcripts.isEmpty {
                    LibraryAskBar(isPresented: $isAsking, question: $askQuestion)
                        .frame(maxWidth: 640)
                }
                if !model.people.isEmpty, model.query.isEmpty {
                    PeopleStrip()
                }
                if model.transcripts.isEmpty {
                    EmptyLibrary()
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("Conversations")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("\(model.transcripts.count)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            SearchField(text: $model.query, focused: $searchFocused)
                                .frame(width: 280)
                        }
                        let results = model.filteredTranscripts
                        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty, !results.isEmpty {
                            SearchResults(transcripts: results, query: model.query)
                        } else if results.isEmpty {
                            ContentUnavailableView.search(text: model.query)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else {
                            if model.query.isEmpty, let latest = results.first {
                                FeaturedCard(transcript: latest, activity: model.activity[latest.id])
                            }
                            let rest = model.query.isEmpty ? Array(results.dropFirst()) : results
                            ForEach(DateSection.group(rest), id: \.title) { section in
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(section.title.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .tracking(0.8)
                                        .foregroundStyle(.secondary)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 18)], spacing: 18) {
                                        ForEach(section.transcripts) { transcript in
                                            ConversationCard(transcript: transcript, activity: model.activity[transcript.id])
                                        }
                                    }
                                }
                                .padding(.top, 10)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .padding(.bottom, 70)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(AmbientBackground())
        .sheet(isPresented: $isAsking) {
            LibraryChatView(question: $askQuestion)
        }
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }
}

/// Greeting plus the record orb: the one thing most people came to do.
private struct Welcome: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 44) {
            VStack(alignment: .leading, spacing: 14) {
                Text(greeting)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    )
                Text(dateline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    SourcePicker()
                        .disabled(model.isRecording)
                    Button {
                        FileImport.presentOpenPanel(model: model)
                    } label: {
                        Label("Import", systemImage: "arrow.down.doc")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassBackground(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .help("Transcribe an audio or video file, or drop it anywhere (⌘O)")
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                RecordButton(size: 132)
                Text(model.isRecording ? "Recording" : "Record")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 20)
        }
        .padding(.vertical, 12)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var dateline: String {
        let date = Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
        let week = model.transcripts.filter { $0.createdAt > Date().addingTimeInterval(-7 * 86_400) }
        let seconds = week.reduce(0) { $0 + $1.duration }
        guard !week.isEmpty else { return date }
        let length = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(date) · \(week.count) this week, \(length) transcribed"
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text("Your conversations will live here")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Each one becomes a readable chat you can play back, search, summarize and ask questions about.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

private struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search conversations", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
            if text.isEmpty {
                Text("⌘F")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            } else {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassBackground(in: Capsule())
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
