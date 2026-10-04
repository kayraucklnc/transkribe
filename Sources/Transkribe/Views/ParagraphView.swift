import SwiftUI
import TranskribeCore

/// One paragraph of the transcript. While it's being played, spoken words are emphasized
/// karaoke-style; search hits are highlighted inline.
struct ParagraphView: View, Equatable {
    let paragraph: Paragraph
    let speakerName: String?
    let showsSpeaker: Bool
    let playhead: TimeInterval?
    let query: String
    let transcriptID: Transcript.ID
    /// All speakers in the transcript, for "Change Speaker".
    let speakers: [Int: String]
    @Environment(PlayerController.self) private var player
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Cheap identity check: a paragraph only changes when it grows or is relabeled.
        lhs.paragraph.id == rhs.paragraph.id && lhs.paragraph.words.count == rhs.paragraph.words.count
            && lhs.paragraph.end == rhs.paragraph.end && lhs.paragraph.speaker == rhs.paragraph.speaker
            && lhs.speakerName == rhs.speakerName
            && lhs.showsSpeaker == rhs.showsSpeaker && lhs.playhead == rhs.playhead && lhs.query == rhs.query
            && lhs.speakers == rhs.speakers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsSpeaker, let speaker = paragraph.speaker, let speakerName {
                HStack(alignment: .center, spacing: 14) {
                    SpeakerAvatar(name: speakerName, speaker: speaker, size: 24)
                        .frame(width: 48, alignment: .trailing)
                    Text(speakerName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.color(for: speaker))
                    timestampButton
                        .padding(.leading, -6)
                }
                .padding(.top, 22)
                .padding(.horizontal, 8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Group {
                    if showsSpeaker {
                        Color.clear.frame(height: 1)
                    } else {
                        timestampButton
                    }
                }
                .frame(width: 48, alignment: .trailing)

                Text(attributedText)
                    .font(.system(size: 16))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(playhead != nil ? Theme.color(for: paragraph.speaker ?? 0).opacity(0.08)
                          : (isHovered ? Color.primary.opacity(0.035) : .clear))
            }
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .animation(.easeOut(duration: 0.2), value: playhead != nil)
        .contextMenu {
            Button("Play from Here") { player.play(from: paragraph.start) }
            Button("Copy Paragraph") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paragraph.text, forType: .string)
            }
            Divider()
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
    }

    private var timestampButton: some View {
        Button { player.play(from: paragraph.start) } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .opacity(isHovered ? 1 : 0)
                Text(TranscriptFormatter.timestamp(paragraph.start))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Play from \(TranscriptFormatter.timestamp(paragraph.start))")
    }

    private var attributedText: AttributedString {
        let terms = TranscriptSearch.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        var result = AttributedString()
        for (index, word) in paragraph.words.enumerated() {
            let text = index == 0 ? String(word.text.drop { $0 == " " }) : word.text
            var piece = AttributedString(text)
            if let playhead {
                piece.foregroundColor = word.start <= playhead ? .primary : .secondary
            }
            if !terms.isEmpty, terms.contains(where: TranscriptSearch.normalize(word.text).contains) {
                piece.backgroundColor = .yellow.opacity(0.45)
            }
            result += piece
        }
        return result
    }
}
