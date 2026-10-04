import SwiftUI
import TranskribeCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(DateSection.group(model.filteredTranscripts), id: \.title) { section in
                Section(section.title) {
                    ForEach(section.transcripts) { transcript in
                        SidebarRow(transcript: transcript, activity: model.activity[transcript.id])
                            .tag(transcript.id)
                            .contextMenu {
                                Button("Copy Transcript") { model.copyText(of: transcript.id) }
                                Button("Show in Finder") { model.revealInFinder(transcript.id) }
                                Divider()
                                Button("Delete", role: .destructive) { model.delete(transcript.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let id = model.selection { model.delete(id) }
        }
        .overlay {
            if model.filteredTranscripts.isEmpty, !model.query.isEmpty {
                ContentUnavailableView.search(text: model.query)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ModelStatusView()
        }
    }
}

/// Groups transcripts like Notes: Today, Yesterday, Previous 7 Days, then by month.
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

private struct SidebarRow: View {
    let transcript: Transcript
    let activity: AppModel.Activity?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(transcript.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(transcript.createdAt, format: Calendar.current.isDateInToday(transcript.createdAt)
                         ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated))
                    Text(TranscriptFormatter.timestamp(transcript.duration))
                    if !transcript.preview.isEmpty {
                        Text(transcript.preview).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var trailing: some View {
        switch (transcript.status, activity) {
        case (_, .transcribing(let progress)?):
            ProgressRing(progress: progress)
        case (_, .identifyingSpeakers?), (.transcribing, nil):
            ProgressView().controlSize(.mini)
        case (.pending, _):
            Image(systemName: "clock").foregroundStyle(.secondary).font(.caption)
        case (.failed, _):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
        case (.done, nil) where transcript.hasSpeakers:
            SpeakerDots(speakers: Array(transcript.speakers.prefix(4)))
        default:
            EmptyView()
        }
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
        }
        .frame(width: 15, height: 15)
    }
}

private struct SpeakerDots: View {
    let speakers: [Int]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(speakers, id: \.self) { speaker in
                Circle()
                    .fill(Theme.color(for: speaker))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// First-run model download / optimization progress.
private struct ModelStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.modelPreparation {
        case .downloading(let fraction):
            status("Downloading speech model", detail: "One time, about 630 MB", value: fraction)
        case .loading(firstTime: true):
            status("Optimizing for this Mac", detail: "First launch only, a minute or two", value: nil)
        case .loading(firstTime: false):
            status("Loading speech model", detail: "Just a moment", value: nil)
        case .ready, nil:
            EmptyView()
        }
    }

    private func status(_ text: String, detail: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(text).font(.caption.weight(.medium))
                Spacer()
                if let value {
                    Text(value.formatted(.percent.precision(.fractionLength(0)))).font(.caption.monospacedDigit())
                }
            }
            Text(detail).font(.caption2).foregroundStyle(.secondary)
            if let value {
                ProgressView(value: value).controlSize(.small)
            } else {
                ProgressView().progressViewStyle(.linear).controlSize(.small)
            }
        }
        .padding(12)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(10)
    }
}
