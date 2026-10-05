import SwiftUI
import TranskribeCore

/// When a recording continues an earlier conversation: the sessions in order, and a glimpse of
/// how the last one ended so you pick up with context.
struct ThreadContext: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model

    var body: some View {
        let sessions = model.sessions(of: transcript)
        if sessions.count > 1 {
            VStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(.tint)
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            let current = session.id == transcript.id
                            Button {
                                withAnimation(Theme.spring) { model.selection = session.id }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Part \(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(current ? .white.opacity(0.85) : .secondary)
                                    Text(session.createdAt.formatted(.dateTime.day().month(.abbreviated)))
                                        .font(.callout.weight(.semibold))
                                }
                                .foregroundStyle(current ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(current ? AnyShapeStyle(Theme.myBubble) : AnyShapeStyle(Theme.card), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(current)
                            if index < sessions.count - 1 {
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                if let index = sessions.firstIndex(where: { $0.id == transcript.id }), index > 0 {
                    PreviousSessionGlimpse(session: sessions[index - 1])
                }
            }
            .padding(.bottom, 20)
        }
    }
}

private struct PreviousSessionGlimpse: View {
    let session: Transcript
    @Environment(AppModel.self) private var model

    var body: some View {
        let tail = Array(session.segments.suffix(3))
        Button {
            withAnimation(Theme.spring) { model.selection = session.id }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Previously · \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(tail) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let speaker = segment.speaker {
                            Text(session.name(of: speaker)).font(.caption.weight(.semibold)).foregroundStyle(Theme.color(for: speaker))
                        }
                        Text(segment.text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the previous part")
    }
}

/// Pick another conversation for this recording to continue.
struct JoinConversationSheet: View {
    let transcript: Transcript
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Continue a conversation").font(.title3.weight(.semibold))
            Text("This recording becomes the next part of the conversation you pick. Each part keeps its own voices and audio.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Search conversations", text: $query).textFieldStyle(.roundedBorder)
            List(candidates) { candidate in
                Button {
                    model.addToConversation(transcript.id, joining: candidate.id)
                    onDone()
                } label: {
                    HStack {
                        if candidate.hasSpeakers { AvatarStack(transcript: candidate, size: 22) }
                        VStack(alignment: .leading) {
                            Text(candidate.title).font(.callout.weight(.medium))
                            Text(candidate.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if candidate.threadID != nil {
                            Text("\(model.sessions(of: candidate).count) parts").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 300)
            HStack {
                Spacer()
                Button("Cancel", action: onDone)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var candidates: [Transcript] {
        model.transcripts.filter { $0.id != transcript.id && ($0.threadID == nil || $0.threadID != transcript.threadID) }
            .filter { query.isEmpty || TranscriptSearch.matches($0, query: query) }
    }
}
