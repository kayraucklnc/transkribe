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
        /// Quick reactions others had while this was being said, shown as tapbacks.
        public var reactions: [Reaction] = []

        public var id: Paragraph.ID { paragraph.id }
    }

    public enum Item: Equatable, Sendable, Identifiable {
        case separator(TimeInterval)
        case bubble(Bubble)

        /// Cheap to hash and compare: lists ask for ids constantly while laying out.
        public enum ID: Hashable, Sendable {
            case separator(Int)
            case bubble(Paragraph.ID)
        }

        public var id: ID {
            switch self {
            case .separator(let time): .separator(Int(time * 1000))
            case .bubble(let bubble): .bubble(bubble.id)
            }
        }
    }

    /// Builds the thread from segments, turning quick reactions into tapbacks on the message
    /// they respond to (only when there are several speakers to react to each other).
    public static func items(for segments: [Segment], me: Int?) -> [Item] {
        let speakers = Set(segments.compactMap(\.speaker))
        guard speakers.count > 1 else { return items(for: ParagraphBuilder.paragraphs(from: segments), me: me) }

        var reactions: [(segment: Segment, kind: Reaction.Kind)] = []
        var messages: [Segment] = []
        for segment in segments {
            if let kind = Reaction.Kind.classify(segment.text), isResponding(segment, among: segments) {
                reactions.append((segment, kind))
            } else {
                messages.append(segment)
            }
        }
        var result = items(for: ParagraphBuilder.paragraphs(from: messages), me: me)
        for (segment, kind) in reactions {
            let reaction = Reaction(id: segment.id, speaker: segment.speaker, kind: kind,
                                    text: segment.text.trimmingCharacters(in: .whitespaces), time: segment.start)
            if let index = target(for: segment, in: result) {
                guard case .bubble(var bubble) = result[index] else { continue }
                bubble.reactions.append(reaction)
                result[index] = .bubble(bubble)
            }
        }
        return result
    }

    /// A reaction responds to someone else: said while they talk, or right after they finish.
    private static func isResponding(_ reaction: Segment, among segments: [Segment]) -> Bool {
        segments.contains { other in
            other.speaker != reaction.speaker && other.id != reaction.id
                && reaction.start >= other.start - 0.3 && reaction.start <= other.end + reactionWindow
                && Reaction.Kind.classify(other.text) == nil
        }
    }

    /// Reactions said within this long after a message still count as responding to it.
    static let reactionWindow: TimeInterval = 1.5

    private static func target(for reaction: Segment, in items: [Item]) -> Int? {
        var best: (index: Int, distance: TimeInterval)?
        for (index, item) in items.enumerated() {
            guard case .bubble(let bubble) = item, bubble.paragraph.speaker != reaction.speaker else { continue }
            let paragraph = bubble.paragraph
            let distance: TimeInterval = reaction.start < paragraph.start ? paragraph.start - reaction.start
                : reaction.start > paragraph.end ? reaction.start - paragraph.end : 0
            if distance <= reactionWindow, distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
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
