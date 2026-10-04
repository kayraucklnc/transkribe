import SwiftUI
import TranskribeCore

/// Renders the Markdown models return (headings, bullet lists, checklists, paragraphs) with
/// `[12:34]` citations as links that jump the player to that moment.
struct MarkdownView: View {
    let markdown: String
    var fontSize: CGFloat = 13.5
    @Environment(PlayerController.self) private var player
    @Environment(AppModel.self) private var model
    /// Called after a link opened a conversation (e.g. to close a sheet).
    var onOpen: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(of: markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if let target = AIModel.openTarget(from: url) {
                model.selectedPerson = nil
                model.open(target.id, at: target.time)
                onOpen()
                return .handled
            }
            guard let seconds = AIModel.seekTime(from: url) else { return .systemAction }
            player.play(from: seconds)
            return .handled
        })
    }

    enum Block {
        case heading(String, level: Int)
        case bullet(String, indent: Int)
        case check(String, done: Bool)
        case numbered(String, number: String)
        case paragraph(String)
    }

    static func blocks(of markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for rawLine in markdown.components(separatedBy: .newlines) {
            let indent = rawLine.prefix { $0 == " " }.count / 2
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                blocks.append(.heading(String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces), level: level))
            } else if let match = line.firstMatch(of: #/^[-*] \[( |x|X)\] (.*)$/#) {
                flush()
                blocks.append(.check(String(match.2), done: match.1 != " "))
            } else if let match = line.firstMatch(of: #/^[-*•] (.*)$/#) {
                flush()
                blocks.append(.bullet(String(match.1), indent: indent))
            } else if let match = line.firstMatch(of: #/^(\d+)[.)] (.*)$/#) {
                flush()
                blocks.append(.numbered(String(match.2), number: String(match.1)))
            } else if line == "---" {
                flush()
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case .heading(let text, let level):
            Text(text.replacingOccurrences(of: "**", with: ""))
                .font(.system(size: level <= 1 ? fontSize + 6 : fontSize + 3, weight: .bold, design: .rounded))
                .padding(.top, 12)
        case .bullet(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .check(let text, let done):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.accentColor : Color.secondary)
                    .font(.system(size: fontSize - 1))
                Text(inline(text))
            }
        case .numbered(let text, let number):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text))
            }
        case .paragraph(let text):
            Text(inline(text))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let linked = AIModel.linkingTimestamps(in: text)
        var result = (try? AttributedString(markdown: linked, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        result.font = .system(size: fontSize)
        // Timestamps are quiet, small and tinted: there when you want to jump, out of the way otherwise.
        for run in result.runs where run.link != nil {
            result[run.range].foregroundColor = .accentColor.opacity(0.8)
            result[run.range].font = .system(size: fontSize - 2.5, weight: .semibold).monospacedDigit()
            result[run.range].baselineOffset = 0.5
        }
        return result
    }
}
