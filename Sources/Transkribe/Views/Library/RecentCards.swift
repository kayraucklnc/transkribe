import SwiftUI
import TranskribeCore

/// The latest conversations as big cards you can't miss; each one wakes up when you point at it.
struct RecentCards: View {
    let transcripts: [Transcript]
    @State private var appeared = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Array(transcripts.enumerated()), id: \.element.id) { index, transcript in
                    RecentCard(transcript: transcript)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15 + Double(index) * 0.06), value: appeared)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .onAppear { appeared = true }
    }
}

private struct RecentCard: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(Theme.spring) { model.selection = transcript.id }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                LiveShape(transcript: transcript, isAwake: isHovered)
                    .frame(height: 74)
                    .padding(.bottom, 22)
                HStack(spacing: 6) {
                    Text(transcript.createdAt.formatted(.relative(presentation: .named)).capitalized)
                    Text("·")
                    Text(TranscriptFormatter.timestamp(transcript.duration)).monospacedDigit()
                    Spacer()
                    StatusBadge(transcript: transcript, activity: model.activity[transcript.id])
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                Text(transcript.title)
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .padding(.top, 6)
                Text(ConversationRow.snippet(for: transcript))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.top, 4)
                Spacer(minLength: 14)
                if transcript.hasSpeakers {
                    HStack(spacing: 8) {
                        AvatarStack(transcript: transcript, size: 22, limit: 3)
                        Text(transcript.speakers.prefix(3).map { transcript.name(of: $0) }.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(20)
            .frame(width: 264, height: 270, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Stage.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.2 : 0.08), lineWidth: 1))
            .shadow(color: .black.opacity(isHovered ? 0.35 : 0.12), radius: isHovered ? 26 : 10, y: isHovered ? 16 : 6)
            .offset(y: isHovered ? -6 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(SquishStyle())
        .onHover { hovering in withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isHovered = hovering } }
        .contextMenu { RowMenu(transcript: transcript) }
    }
}

/// The conversation's shape in speaker colors; on hover the bars ripple as if playing.
private struct LiveShape: View {
    let transcript: Transcript
    let isAwake: Bool
    private let count = 34

    var body: some View {
        let bins = ActivityBins.make(segments: transcript.segments, duration: transcript.duration, count: count)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAwake)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let gap: CGFloat = 3
                let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                for (index, bin) in bins.enumerated() {
                    let wave = isAwake ? 0.78 + 0.22 * sin(time * 7 - Double(index) * 0.5) : 1
                    let level = bin.level > 0 ? (0.18 + 0.82 * bin.level) * wave : 0
                    let height = max(width, CGFloat(level) * size.height)
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                    let color = bin.level > 0 ? Theme.color(for: bin.speaker ?? 0) : Color.primary.opacity(0.12)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
