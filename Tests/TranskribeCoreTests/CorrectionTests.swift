import Foundation
import Testing
@testable import TranskribeCore

@Suite struct CorrectionLearnerTests {
    @Test func misheardWordsBecomeVocabulary() {
        #expect(CorrectionLearner.newTerms(from: "Call Kayrah about the trans cribe demo", to: "Call Kayra about the Transkribe demo",
                                           known: []) == ["Kayra", "Transkribe"])
    }

    @Test func plainRewritesTeachNothing() {
        // Added and removed words aren't mishearings; common words aren't worth learning.
        #expect(CorrectionLearner.newTerms(from: "we will meet tomorrow", to: "we will definitely meet tomorrow", known: []).isEmpty)
        #expect(CorrectionLearner.newTerms(from: "it was a good day", to: "it was the good day", known: []).isEmpty)
    }

    @Test func alreadyKnownWordsAreSkipped() {
        #expect(CorrectionLearner.newTerms(from: "ask Hacan", to: "ask Hakan", known: ["hakan"]).isEmpty)
    }

    @Test func punctuationIsIgnored() {
        #expect(CorrectionLearner.newTerms(from: "Thanks, Gemany.", to: "Thanks, Gemini.", known: []) == ["Gemini"])
    }
}

@Suite struct SegmentEditingTests {
    @Test func editedTextReplacesTheParagraphKeepingItsTimes() {
        let a = Segment(start: 10, end: 12, text: "Hello there", speaker: 1)
        let b = Segment(start: 12, end: 14, text: "general kenobi", speaker: 1)
        let c = Segment(start: 20, end: 22, text: "untouched", speaker: 2)
        let edited = SegmentEditing.replacing([a.id, b.id], in: [a, b, c], with: "Hello there, General Kenobi.")
        #expect(edited.count == 2)
        #expect(edited[0].id == a.id)
        #expect(edited[0].text == "Hello there, General Kenobi.")
        #expect(edited[0].start == 10 && edited[0].end == 14)
        #expect(edited[0].words.map(\.text) == ["Hello", " there,", " General", " Kenobi."])
        #expect(edited[0].words.first?.start == 10 && edited[0].words.last?.end == 14)
        #expect(edited[1] == c)
    }

    @Test func emptyTextRemovesTheParagraph() {
        let a = Segment(start: 0, end: 1, text: "um", speaker: 1)
        #expect(SegmentEditing.replacing([a.id], in: [a], with: "  ").isEmpty)
    }
}
