import Testing
@testable import TranskribeCore

@Suite struct ChatLayoutTests {
    private func paragraphs(_ items: [(Double, Int?)]) -> [Paragraph] {
        ParagraphBuilder.paragraphs(from: items.map { Segment(start: $0.0, end: $0.0 + 3, text: "t\($0.0)", speaker: $0.1) })
    }

    private func bubbles(_ items: [ChatLayout.Item]) -> [ChatLayout.Bubble] {
        items.compactMap { if case .bubble(let bubble) = $0 { bubble } else { nil } }
    }

    @Test func meGoesRightEveryoneElseLeft() {
        let items = ChatLayout.items(for: paragraphs([(0, 1), (10, 2), (20, 1)]), me: 2)
        #expect(bubbles(items).map(\.isMine) == [false, true, false])
    }

    @Test func withoutMeEveryoneIsOnTheLeftWithNames() {
        let result = bubbles(ChatLayout.items(for: paragraphs([(0, 1), (10, 2)]), me: nil))
        #expect(result.allSatisfy { !$0.isMine })
        #expect(result.allSatisfy { $0.showsName })
    }

    @Test func groupsConsecutiveBubblesFromTheSameSpeaker() {
        // Paragraphs split by long pauses but same speaker form one visual group.
        let result = bubbles(ChatLayout.items(for: paragraphs([(0, 1), (40, 1), (80, 2)]), me: 2))
        #expect(result.map(\.isFirstInGroup) == [true, false, true])
        #expect(result.map(\.isLastInGroup) == [false, true, true])
        #expect(result.map(\.showsName) == [false, false, false]) // 1:1 chat: no names
    }

    @Test func namesOnlyForOthersWhenTheyAreSeveral() {
        let one = bubbles(ChatLayout.items(for: paragraphs([(0, 1), (10, 2)]), me: 2))
        #expect(one.first?.showsName == false) // a 1:1 chat needs no names, like iMessage
        let many = bubbles(ChatLayout.items(for: paragraphs([(0, 1), (10, 3), (20, 2)]), me: 2))
        #expect(many.filter { !$0.isMine }.allSatisfy { $0.showsName })
    }

    @Test func insertsTimeSeparatorsAfterLongGaps() {
        let items = ChatLayout.items(for: paragraphs([(0, 1), (10, 2), (400, 1)]), me: 2)
        let separators = items.compactMap { if case .separator(let time) = $0 { time } else { nil } }
        #expect(separators == [0, 400])
        #expect(items.first == .separator(0))
    }

    @Test func itemIDsAreStable() {
        let input = paragraphs([(0, 1), (10, 2)])
        #expect(ChatLayout.items(for: input, me: 1).map(\.id) == ChatLayout.items(for: input, me: 1).map(\.id))
    }
}
