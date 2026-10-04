import SwiftUI
import TranskribeCore

/// Matching lines across every conversation; click one to jump right to it.
struct SearchResults: View {
    let transcripts: [Transcript]
    let query: String
    /// When searching by meaning: every word that counts as a match.
    var terms: [String]?
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(transcripts) { transcript in
                let hits = terms.map { MeaningSearch.hits(in: transcript, terms: $0) } ?? TranscriptSearch.hits(in: transcript, query: query)
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(Theme.spring) { model.open(transcript.id, at: hits.first?.start) }
                    } label: {
                        HStack(spacing: 10) {
                            if transcript.hasSpeakers { AvatarStack(transcript: transcript, size: 22) }
                            Text(transcript.title)
                                .font(.system(.headline, design: .rounded))
                            Text(hits.isEmpty ? "Title" : "\(hits.count) \(hits.count == 1 ? "match" : "matches")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(transcript.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 6)
                    ForEach(hits.prefix(4)) { hit in
                        HitRow(transcript: transcript, hit: hit, query: terms?.joined(separator: " ") ?? query)
                    }
                    if hits.count > 4 {
                        Button("Show all \(hits.count) in conversation") {
                            withAnimation(Theme.spring) { model.open(transcript.id, at: hits.first?.start) }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.leading, 8)
                    }
                }
                .padding(18)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.06)))
            }
        }
    }
}

private struct HitRow: View {
    let transcript: Transcript
    let hit: TranscriptSearch.Hit
    let query: String
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(Theme.spring) { model.open(transcript.id, at: hit.start) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TranscriptFormatter.timestamp(hit.start))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                if let speaker = hit.speaker, transcript.hasSpeakers {
                    Text(transcript.name(of: speaker))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.color(for: speaker))
                }
                Text(Highlight.attributed(hit.text, query: query))
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Marks search terms inside a line, ignoring case and accents.
enum Highlight {
    static func attributed(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        let terms = TranscriptSearch.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return result }
        var index = result.startIndex
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let length = word.count
            let end = result.index(index, offsetByCharacters: length)
            if terms.contains(where: TranscriptSearch.normalize(String(word)).contains) {
                result[index..<end].backgroundColor = .yellow.opacity(0.5)
                result[index..<end].foregroundColor = .primary
            }
            index = end < result.endIndex ? result.index(afterCharacter: end) : end
        }
        return result
    }
}
