import Testing
@testable import TranskribeCore

@Suite struct ParagraphBuilderTests {
    @Test func joinsSegmentsSeparatedBySmallGaps() {
        let paragraphs = ParagraphBuilder.paragraphs(from: [
            Segment(start: 0, end: 2, text: "Alo?"),
            Segment(start: 2.5, end: 4, text: "Napıyorsun?"),
        ])
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Alo? Napıyorsun?")
        #expect(paragraphs[0].start == 0)
    }

    @Test func breaksOnLongPauses() {
        let paragraphs = ParagraphBuilder.paragraphs(from: [
            Segment(start: 0, end: 2, text: "Before the pause."),
            Segment(start: 10, end: 12, text: "After the pause."),
        ])
        #expect(paragraphs.map(\.text) == ["Before the pause.", "After the pause."])
    }

    @Test func breaksOnSpeakerChange() {
        let paragraphs = ParagraphBuilder.paragraphs(from: [
            Segment(start: 0, end: 1, text: "Hi.", speaker: 1),
            Segment(start: 1, end: 2, text: "Hello.", speaker: 2),
        ])
        #expect(paragraphs.map(\.speaker) == [1, 2])
    }

    @Test func capsParagraphLength() {
        let segments = (0..<20).map { Segment(start: Double($0) * 5, end: Double($0) * 5 + 5, text: "Sentence \($0).") }
        let paragraphs = ParagraphBuilder.paragraphs(from: segments)
        #expect(paragraphs.count > 1)
        #expect(paragraphs.allSatisfy { $0.end - $0.start <= ParagraphBuilder.maxDuration + 5 })
        #expect(paragraphs.flatMap(\.segmentIDs) == segments.map(\.id))
    }

    @Test func collectsWordsAndSynthesizesThemWhenMissing() {
        let paragraphs = ParagraphBuilder.paragraphs(from: [
            Segment(start: 0, end: 1, text: "Hello world", words: [Word(start: 0, end: 0.5, text: " Hello"), Word(start: 0.5, end: 1, text: " world")]),
            Segment(start: 1.2, end: 2, text: "Again"),
        ])
        #expect(paragraphs[0].words.map(\.text) == [" Hello", " world", " Again"])
        #expect(paragraphs[0].words.last?.start == 1.2)
    }

    @Test func paragraphIDIsStableAcrossRebuilds() {
        let segments = [Segment(start: 0, end: 1, text: "One"), Segment(start: 1, end: 2, text: "Two")]
        #expect(ParagraphBuilder.paragraphs(from: segments).map(\.id) == ParagraphBuilder.paragraphs(from: segments).map(\.id))
    }
}
