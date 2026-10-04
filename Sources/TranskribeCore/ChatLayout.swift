import Foundation

/// Lays a transcript out like a messaging thread: the user's own words on the right,
/// everyone else on the left, grouped by speaker, with time separators after long pauses.
public enum ChatLayout {
    /// A pause this long starts a new section with its own timestamp.
    static let separatorGap: TimeInterval = 120

    public struct Bubble: Equatable, Sendable, Identifiable {
        public var paragraph: Paragraph
        public var isMine: Bool
        public var isFirstInGroup: Bool
        public var isLastInGroup: Bool
        /// Show the speaker's name above the bubble (first bubble of a group in a group chat).
        public var showsName: Bool

        public var id: Paragraph.ID { paragraph.id }
    }

    public enum Item: Equatable, Sendable, Identifiable {
        case separator(TimeInterval)
        case bubble(Bubble)

        public var id: String {
            switch self {
            case .separator(let time): "separator-\(Int(time * 1000))"
            case .bubble(let bubble): bubble.id.uuidString
            }
        }
    }

    public static func items(for paragraphs: [Paragraph], me: Int?) -> [Item] {
        let others = Set(paragraphs.compactMap(\.speaker).filter { $0 != me })
        let isGroupChat = me == nil || others.count > 1
        var items: [Item] = []
        var previousEnd: TimeInterval?

        for (index, paragraph) in paragraphs.enumerated() {
            if previousEnd.map({ paragraph.start - $0 >= separatorGap }) ?? true {
                items.append(.separator(paragraph.start))
            }
            let before = index > 0 ? paragraphs[index - 1] : nil
            let after = index < paragraphs.count - 1 ? paragraphs[index + 1] : nil
            let startsSection = previousEnd.map { paragraph.start - $0 >= separatorGap } ?? true
            let continuesSection = after.map { $0.start - paragraph.end < separatorGap } ?? false
            let isFirst = startsSection || before?.speaker != paragraph.speaker
            let isLast = !continuesSection || after?.speaker != paragraph.speaker
            let isMine = me != nil && paragraph.speaker == me
            items.append(.bubble(Bubble(
                paragraph: paragraph,
                isMine: isMine,
                isFirstInGroup: isFirst,
                isLastInGroup: isLast,
                showsName: isFirst && !isMine && isGroupChat && paragraph.speaker != nil
            )))
            previousEnd = paragraph.end
        }
        return items
    }
}
