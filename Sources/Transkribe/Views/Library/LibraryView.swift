import SwiftUI
import TranskribeCore

/// Home: start a recording, or pick up any past conversation.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                RecordHero()
                if model.transcripts.isEmpty {
                    EmptyLibrary()
                } else {
                    HStack {
                        Text("Conversations")
                            .font(.title2.weight(.bold))
                        Spacer()
                        SearchField(text: $model.query, focused: $searchFocused)
                            .frame(width: 260)
                    }
                    let sections = DateSection.group(model.filteredTranscripts)
                    if sections.isEmpty {
                        ContentUnavailableView.search(text: model.query)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 18)], spacing: 18) {
                                ForEach(section.transcripts) { transcript in
                                    ConversationCard(transcript: transcript, activity: model.activity[transcript.id])
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }
}

/// The big call to action: record, with the source right next to it.
private struct RecordHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 26) {
            RecordButton(size: 84)
            VStack(alignment: .leading, spacing: 10) {
                Text(model.isRecording ? "Recording…" : "New conversation")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Record, or drop any audio or video file. Every language, on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    SourcePicker()
                        .disabled(model.isRecording)
                    Button {
                        FileImport.presentOpenPanel(model: model)
                    } label: {
                        Label("Import File", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .help("Transcribe an audio or video file (⌘O)")
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 6)
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Your conversations will appear here")
                .font(.title3.weight(.medium))
            Text("Each one becomes a readable chat you can play back, search, summarize and ask questions about.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }
}

private struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search everything", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
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
