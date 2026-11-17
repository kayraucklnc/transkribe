import SwiftUI
import TranskribeCore

/// The latest conversations as a grid of cards, aligned to the page like everything else.
struct RecentCards: View {
    let transcripts: [Transcript]
    @State private var appeared = false

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(Array(transcripts.enumerated()), id: \.element.id) { index, transcript in
                RecentCard(transcript: transcript)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(.easeOut(duration: 0.4).delay(0.1 + Double(index) * 0.035), value: appeared)
            }
        }
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
                HStack(spacing: 6) {
                    Text(RecentCardFormat.when(transcript.createdAt))
                    Spacer(minLength: 8)
                    StatusBadge(transcript: transcript, activity: model.activity[transcript.id])
                    Text(RecentCardFormat.length(transcript.duration))
                        .monospacedDigit()
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                Text(transcript.title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
                    .padding(.top, 10)
                Text(ConversationRow.snippet(for: transcript))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .lineSpacing(1.5)
                    .padding(.top, 4)
                Spacer(minLength: 16)
                SpeakerStrip(segments: transcript.segments, duration: transcript.duration, height: 3)
                HStack(spacing: 8) {
                    if transcript.hasSpeakers {
                        AvatarStack(transcript: transcript, size: 18, limit: 3)
                        Text(transcript.speakers.prefix(3).map { transcript.name(of: $0) }.joined(separator: ", "))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(height: 18)
                .padding(.top, 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? Stage.cardRaised : Stage.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0.07), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SquishStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
        .contextMenu { RowMenu(transcript: transcript) }
    }
}

/// How a card says when a conversation happened and how long it ran.
enum RecentCardFormat {
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today, \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func length(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else {
            return Duration.seconds(max(0, seconds.rounded())).formatted(.units(allowed: [.seconds], width: .abbreviated))
        }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
