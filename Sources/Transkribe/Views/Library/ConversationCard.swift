import SwiftUI
import TranskribeCore

struct ConversationCard: View {
    let transcript: Transcript
    let activity: AppModel.Activity?
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(Theme.spring) { model.selection = transcript.id }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transcript.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    status
                }
                Text(snippet)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                SpeakerStrip(segments: transcript.segments, duration: transcript.duration)
                HStack {
                    if transcript.hasSpeakers {
                        AvatarStack(transcript: transcript, size: 22)
                        Text("\(transcript.speakers.count) people")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let code = transcript.language, let name = Locale.current.localizedString(forLanguageCode: code) {
                        Text(name.capitalized(with: Locale.current))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(isHovered ? 0.12 : 0.05)))
            .shadow(color: .black.opacity(isHovered ? 0.14 : 0.05), radius: isHovered ? 20 : 10, y: isHovered ? 10 : 4)
            .scaleEffect(isHovered ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Theme.spring) { isHovered = hovering } }
        .contextMenu {
            Button("Open") { model.selection = transcript.id }
            Button("Copy Transcript") { model.copyText(of: transcript.id) }
            Button("Show in Finder") { model.revealInFinder(transcript.id) }
            Divider()
            Button("Delete", role: .destructive) { model.delete(transcript.id) }
        }
    }

    private var meta: String {
        let time = Calendar.current.isDateInToday(transcript.createdAt)
            ? transcript.createdAt.formatted(date: .omitted, time: .shortened)
            : transcript.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "\(time) · \(TranscriptFormatter.timestamp(transcript.duration))"
    }

    private var snippet: String {
        if let summary = transcript.summary {
            // First prose line of the summary, without Markdown syntax.
            let line = summary.markdown.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("-") }
            if let line { return line.replacingOccurrences(of: #"\*\*|\[\d+:\d+(:\d+)?\]"#, with: "", options: .regularExpression) }
        }
        let text = transcript.segments.prefix(8).map(\.text).joined(separator: " ")
        switch transcript.status {
        case .pending where text.isEmpty: return "Waiting to transcribe…"
        case .failed(let message): return message
        default: return text.isEmpty ? "Listening…" : text
        }
    }

    @ViewBuilder private var status: some View {
        switch activity {
        case .live?:
            Text("LIVE")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.record, in: Capsule())
        case .transcribing(let progress)?:
            ProgressRing(progress: progress)
        case .identifyingSpeakers?:
            ProgressView().controlSize(.small)
        case nil:
            if case .failed = transcript.status {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
        }
        .frame(width: 20, height: 20)
        .help("Transcribing \(progress.formatted(.percent.precision(.fractionLength(0))))")
    }
}
