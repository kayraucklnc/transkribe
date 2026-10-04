import SwiftUI
import TranskribeCore

/// Shared bits of a conversation preview.
private struct CardInfo {
    let transcript: Transcript

    var snippet: String {
        if let summary = transcript.summary {
            let line = summary.markdown.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("-") }
            if let line { return line.replacingOccurrences(of: #"\*\*|\[\d+:\d+(:\d+)?\]"#, with: "", options: .regularExpression) }
        }
        let text = transcript.segments.prefix(10).map(\.text).joined(separator: " ")
        switch transcript.status {
        case .pending where text.isEmpty: return "Waiting to transcribe…"
        case .failed(let message): return message
        default: return text.isEmpty ? "Listening…" : text
        }
    }

    var when: String {
        Calendar.current.isDateInToday(transcript.createdAt)
            ? transcript.createdAt.formatted(date: .omitted, time: .shortened)
            : transcript.createdAt.formatted(.dateTime.day().month(.abbreviated))
    }

    var flag: String? {
        switch transcript.language {
        case "tr": "🇹🇷"
        case "en": "🇬🇧"
        case "it": "🇮🇹"
        default: nil
        }
    }

    /// A soft glow in the color of whoever talked most.
    var tint: Color {
        Theme.color(for: SpeakerStats.shares(of: transcript.segments).first?.speaker ?? 0)
    }
}

/// Waveform-like bars: how much was said over time, colored by who said it.
struct ActivityBars: View {
    let transcript: Transcript
    var count = 56

    var body: some View {
        let bins = ActivityBins.make(segments: transcript.segments, duration: transcript.duration, count: count)
        Canvas { context, size in
            let gap: CGFloat = 2
            let width = max(1.5, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for (index, bin) in bins.enumerated() {
                let height = max(3, CGFloat(0.15 + 0.85 * bin.level) * size.height * (bin.level > 0 ? 1 : 0.15))
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                let color = bin.level > 0 ? Theme.color(for: bin.speaker ?? 0) : Color.primary.opacity(0.12)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color.opacity(bin.level > 0 ? 0.9 : 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ConversationCard: View {
    let transcript: Transcript
    let activity: AppModel.Activity?
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        let info = CardInfo(transcript: transcript)
        Button {
            withAnimation(Theme.spring) { model.selection = transcript.id }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if transcript.hasSpeakers {
                        AvatarStack(transcript: transcript, size: 24)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(info.tint)
                            .frame(width: 24, height: 24)
                            .background(info.tint.opacity(0.15), in: Circle())
                    }
                    Spacer()
                    StatusBadge(transcript: transcript, activity: activity)
                }
                Text(transcript.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(info.snippet)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                ActivityBars(transcript: transcript, count: 44)
                    .frame(height: 22)
                HStack(spacing: 10) {
                    Label(TranscriptFormatter.timestamp(transcript.duration), systemImage: "clock")
                    Text(info.when)
                    if let flag = info.flag { Text(flag) }
                    Spacer()
                    if transcript.summary != nil {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                            .help("Summarized")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .background {
                // Glows live in an overlay so they can never change the card's size.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(info.tint.opacity(isHovered ? 0.22 : 0.12))
                            .frame(width: 220, height: 220)
                            .blur(radius: 60)
                            .offset(x: -70, y: -90)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(isHovered ? 0.14 : 0.06)))
            .shadow(color: .black.opacity(isHovered ? 0.16 : 0.06), radius: isHovered ? 24 : 12, y: isHovered ? 12 : 5)
            .offset(y: isHovered ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isHovered = hovering } }
        .contextMenu { CardMenu(transcript: transcript) }
    }
}

/// The most recent conversation, presented large so picking up where you left off is one click.
struct FeaturedCard: View {
    let transcript: Transcript
    let activity: AppModel.Activity?
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        let info = CardInfo(transcript: transcript)
        Button {
            withAnimation(Theme.spring) { model.selection = transcript.id }
        } label: {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("LATEST")
                            .font(.caption2.weight(.heavy))
                            .tracking(1)
                            .foregroundStyle(info.tint)
                        StatusBadge(transcript: transcript, activity: activity)
                    }
                    Text(transcript.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(info.snippet)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    HStack(spacing: 14) {
                        Label(TranscriptFormatter.timestamp(transcript.duration), systemImage: "clock")
                        Text(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))
                        if let flag = info.flag { Text(flag) }
                        if transcript.summary != nil {
                            Label("Summarized", systemImage: "sparkles").foregroundStyle(.tint)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 18) {
                    if transcript.hasSpeakers {
                        HStack(spacing: 10) {
                            AvatarStack(transcript: transcript, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(transcript.speakers.prefix(2), id: \.self) { speaker in
                                    Text(transcript.name(of: speaker))
                                        .font(.callout.weight(.medium))
                                }
                            }
                        }
                    }
                    ActivityBars(transcript: transcript, count: 60)
                        .frame(width: 320, height: 64)
                    Label("Open", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.myBubble, in: Capsule())
                }
            }
            .padding(26)
            .frame(minHeight: 200)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.card)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(info.tint.opacity(isHovered ? 0.28 : 0.18))
                            .frame(width: 380, height: 380)
                            .blur(radius: 90)
                            .offset(x: -110, y: -170)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(width: 300, height: 300)
                            .blur(radius: 90)
                            .offset(x: 80, y: 120)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(isHovered ? 0.14 : 0.07)))
            .shadow(color: .black.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 30 : 16, y: isHovered ? 14 : 6)
            .offset(y: isHovered ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isHovered = hovering } }
        .contextMenu { CardMenu(transcript: transcript) }
    }
}

private struct CardMenu: View {
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

private struct StatusBadge: View {
    let transcript: Transcript
    let activity: AppModel.Activity?

    var body: some View {
        switch activity {
        case .live?:
            Label("LIVE", systemImage: "record.circle.fill")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.record, in: Capsule())
        case .transcribing(let progress)?:
            ProgressRing(progress: progress)
        case .identifyingSpeakers?:
            ProgressView().controlSize(.small)
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
