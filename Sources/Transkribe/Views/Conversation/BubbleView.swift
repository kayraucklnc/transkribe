import SwiftUI
import TranskribeCore

/// One message bubble. The user's own words are blue on the right; everyone else is gray on the
/// left, with a name above the first bubble of a group and an avatar beside the last one.
struct BubbleView: View, Equatable {
    let bubble: ChatLayout.Bubble
    let name: String?
    let showsAvatar: Bool
    let playhead: TimeInterval?
    let query: String
    let transcriptID: Transcript.ID
    let speakers: [Int: String]
    /// Briefly highlighted after jumping here from search.
    var isFlashing = false
    @Environment(PlayerController.self) private var player
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bubble.id == rhs.bubble.id && lhs.bubble.isMine == rhs.bubble.isMine
            && lhs.bubble.isFirstInGroup == rhs.bubble.isFirstInGroup && lhs.bubble.isLastInGroup == rhs.bubble.isLastInGroup
            && lhs.bubble.showsName == rhs.bubble.showsName
            && lhs.bubble.paragraph.words.count == rhs.bubble.paragraph.words.count
            && lhs.bubble.paragraph.end == rhs.bubble.paragraph.end && lhs.bubble.paragraph.speaker == rhs.bubble.paragraph.speaker
            && lhs.name == rhs.name && lhs.showsAvatar == rhs.showsAvatar && lhs.playhead == rhs.playhead
            && lhs.query == rhs.query && lhs.speakers == rhs.speakers && lhs.isFlashing == rhs.isFlashing
    }

    private var paragraph: Paragraph { bubble.paragraph }
    private var mine: Bool { bubble.isMine }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if bubble.showsName, let name {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.color(for: paragraph.speaker))
                    .padding(.leading, avatarWidth + 14)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 80) }
                if !mine {
                    avatar
                }
                if mine { timestamp }
                bubbleBody
                if !mine { timestamp }
                if !mine { Spacer(minLength: 80) }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.top, bubble.isFirstInGroup ? 10 : 2)
        .onHover { isHovered = $0 }
        .contextMenu { menu }
    }

    private var bubbleBody: some View {
        CappedWidth(maximum: 500) {
            Text(attributedText)
                .font(.system(size: 15))
                .lineSpacing(2.5)
                .foregroundStyle(mine ? Color.white : Color.primary)
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                let shape = bubbleShape
                if mine {
                    shape.fill(Theme.myBubble)
                } else {
                    shape.fill(Theme.theirBubble)
                    if labelsColor {
                        shape.fill(Theme.color(for: paragraph.speaker).opacity(0.10))
                    }
                }
            }
            .shadow(color: isFlashing ? Color.yellow.opacity(0.9) : .clear, radius: isFlashing ? 14 : 0)
            .overlay {
                if isFlashing {
                    bubbleShape.stroke(Color.yellow, lineWidth: 2.5)
                } else if playhead != nil {
                    bubbleShape.stroke(mine ? Color.white.opacity(0.6) : Theme.color(for: paragraph.speaker).opacity(0.7), lineWidth: 2)
                }
            }

            // Click to listen. (Selectable text would swallow the click; Copy is in the context menu.)
            .contentShape(bubbleShape)
            .onTapGesture { player.play(from: paragraph.start) }
            .help("Click to play from \(TranscriptFormatter.timestamp(paragraph.start))")
    }

    /// Tinting helps tell apart three or more people; a 1:1 chat stays plain gray like iMessage.
    private var labelsColor: Bool { speakers.count > 2 }

    /// Rounded like iMessage: the corner on the speaker's side tightens inside a group.
    private var bubbleShape: UnevenRoundedRectangle {
        let big: CGFloat = 19, small: CGFloat = 6
        let top = bubble.isFirstInGroup ? big : small
        let bottom = bubble.isLastInGroup ? big : small
        return mine
            ? UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: big, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: big, topTrailingRadius: big, style: .continuous)
    }

    private var avatarWidth: CGFloat { showsAvatar ? 28 : 0 }

    @ViewBuilder private var avatar: some View {
        if showsAvatar {
            Group {
                if bubble.isLastInGroup, let speaker = paragraph.speaker, let name {
                    SpeakerAvatar(name: name, speaker: speaker, size: 28)
                } else {
                    Color.clear
                }
            }
            .frame(width: 28, height: 28)
        }
    }

    private var timestamp: some View {
        Button { player.play(from: paragraph.start) } label: {
            HStack(spacing: 3) {
                Image(systemName: "play.fill").font(.system(size: 7))
                Text(TranscriptFormatter.timestamp(paragraph.start))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Play from here")
    }

    @ViewBuilder private var menu: some View {
        Button("Play from Here") { player.play(from: paragraph.start) }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paragraph.text, forType: .string)
        }
        Divider()
        if let speaker = paragraph.speaker {
            Button(mine ? "This Isn't Me" : "This Is Me") {
                model.setMe(mine ? nil : speaker, in: transcriptID)
            }
        }
        Menu("Change Speaker") {
            ForEach(speakers.keys.sorted(), id: \.self) { speaker in
                Button(speakers[speaker] ?? "") {
                    model.assignSpeaker(speaker, to: paragraph.segmentIDs, in: transcriptID)
                }
                .disabled(speaker == paragraph.speaker)
            }
            Divider()
            Button("New Speaker") { model.assignSpeaker(nil, to: paragraph.segmentIDs, in: transcriptID) }
        }
    }

    private var attributedText: AttributedString {
        let terms = TranscriptSearch.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        var result = AttributedString()
        for (index, word) in paragraph.words.enumerated() {
            let text = index == 0 ? String(word.text.drop { $0 == " " }) : word.text
            var piece = AttributedString(text)
            if let playhead, word.start > playhead {
                piece.foregroundColor = mine ? .white.opacity(0.55) : .secondary
            }
            if !terms.isEmpty, terms.contains(where: TranscriptSearch.normalize(word.text).contains) {
                piece.backgroundColor = .yellow.opacity(0.55)
                piece.foregroundColor = .black
            }
            result += piece
        }
        return result
    }
}

/// Wraps text at `maximum` points but lets short text stay as narrow as it is, like a chat bubble.
private struct CappedWidth: Layout {
    var maximum: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(proposal.width ?? maximum, maximum)
        return child.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
