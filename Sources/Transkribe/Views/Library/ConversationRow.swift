import SwiftUI
import TranskribeCore

/// A day's conversations in one rounded group, like a Settings or Notes list.
struct ConversationGroup: View {
    let title: String
    let transcripts: [Transcript]
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(transcripts.enumerated()), id: \.element.id) { index, transcript in
                    ConversationRow(transcript: transcript, activity: model.activity[transcript.id])
                    if index < transcripts.count - 1 {
                        Rectangle().fill(Stage.hairline).frame(height: 0.5).padding(.leading, 62)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Stage.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Stage.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct ConversationRow: View {
    let transcript: Transcript
    let activity: AppModel.Activity?
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(Theme.spring) { model.selection = transcript.id }
        } label: {
            HStack(spacing: 12) {
                leading
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(transcript.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                        StatusBadge(transcript: transcript, activity: activity)
                    }
                    Text(snippet)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 16)
                SpeechShape(transcript: transcript)
                    .frame(width: 84, height: 18)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(when)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(TranscriptFormatter.timestamp(transcript.duration))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovered ? Color.primary.opacity(0.045) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu { RowMenu(transcript: transcript) }
    }

    @ViewBuilder private var leading: some View {
        if transcript.hasSpeakers {
            AvatarStack(transcript: transcript, size: transcript.speakers.count > 1 ? 26 : 34, limit: 2)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
    }

    private var snippet: String { Self.snippet(for: transcript) }

    static func snippet(for transcript: Transcript) -> String {
        if let summary = transcript.summary {
            let line = summary.markdown.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("-") }
            if let line { return line.replacingOccurrences(of: #"\*\*|\[\d+:\d+(:\d+)?\]"#, with: "", options: .regularExpression) }
        }
        let text = transcript.segments.prefix(6).map(\.text).joined(separator: " ")
        switch transcript.status {
        case .pending where text.isEmpty: return "Waiting to transcribe"
        case .failed(let message): return message
        default: return text.isEmpty ? "Listening…" : text
        }
    }

    private var when: String {
        let date = transcript.createdAt
        if Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The shape of a conversation: when people talked, you in the accent color, others in gray.
struct SpeechShape: View {
    let transcript: Transcript
    var count = 28

    var body: some View {
        let bins = ActivityBins.make(segments: transcript.segments, duration: transcript.duration, count: count)
        let me = transcript.resolvedMeSpeaker
        Canvas { context, size in
            let gap: CGFloat = 1.5
            let width = max(1.5, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for (index, bin) in bins.enumerated() {
                let height = bin.level > 0 ? max(3, CGFloat(0.2 + 0.8 * bin.level) * size.height) : 2
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                let color: Color = bin.level == 0 ? .primary.opacity(0.1)
                    : (me != nil && bin.speaker == me ? .accentColor : .primary.opacity(0.35))
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

struct RowMenu: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Open") { model.selection = transcript.id }
        Button("Copy Transcript") { model.copyText(of: transcript.id) }
        Button("Show in Finder") { model.revealInFinder(transcript.id) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(transcript.id) }
    }
}

struct StatusBadge: View {
    let transcript: Transcript
    let activity: AppModel.Activity?

    var body: some View {
        switch activity {
        case .live?:
            Text("LIVE")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Theme.record, in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        case .transcribing(let progress)?:
            ProgressRing(progress: progress)
        case .identifyingSpeakers?:
            ProgressView().controlSize(.mini)
        case .paused(let reason)?:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.secondary)
                .help("Paused: \(reason). Resumes automatically.")
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
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
        }
        .frame(width: 13, height: 13)
        .help("Transcribing \(progress.formatted(.percent.precision(.fractionLength(0))))")
    }
}
