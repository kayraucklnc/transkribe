import Testing
@testable import TranskribeCore

@Suite struct TranscriptSearchTests {
    @Test func emptyQueryMatchesEverything() {
        #expect(TranscriptSearch.matches(Fixtures.transcript(), query: "  "))
    }

    @Test func matchesTitleCaseInsensitively() {
        #expect(TranscriptSearch.matches(Fixtures.transcript(), query: "WEEKLY"))
    }

    @Test func matchesTurkishTextWithoutDiacritics() {
        let transcript = Fixtures.transcript(segments: [Segment(start: 0, end: 1, text: "İstanbul'da güzel bir gün")])
        #expect(TranscriptSearch.matches(transcript, query: "istanbul"))
        #expect(TranscriptSearch.matches(transcript, query: "guzel"))
        #expect(TranscriptSearch.matches(transcript, query: "GÜZEL"))
    }

    @Test func dotlessIMatchesI() {
        let transcript = Fixtures.transcript(segments: [Segment(start: 0, end: 1, text: "nasılsın")])
        #expect(TranscriptSearch.matches(transcript, query: "nasilsin"))
    }

    @Test func requiresEveryWord() {
        let transcript = Fixtures.transcript()
        #expect(TranscriptSearch.matches(transcript, query: "merhaba tesekkurler"))
        #expect(!TranscriptSearch.matches(transcript, query: "merhaba pizza"))
    }

    @Test func findsMatchingSegmentIndices() {
        let transcript = Fixtures.transcript()
        #expect(TranscriptSearch.matchingSegmentIDs(in: transcript, query: "iyiyim") == [transcript.segments[1].id])
        #expect(TranscriptSearch.matchingSegmentIDs(in: transcript, query: "").isEmpty)
    }
}

@Suite struct SearchHitTests {
    private func transcript(_ texts: [String]) -> Transcript {
        Fixtures.transcript(segments: texts.enumerated().map { Segment(start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 5, text: $0.element) })
    }

    @Test func findsMatchingLinesInOrder() {
        let hits = TranscriptSearch.hits(in: transcript(["Merhaba nasılsın", "Fiyat ne kadar?", "Fiyatı Pazartesi konuşalım"]), query: "fiyat")
        #expect(hits.map(\.start) == [10, 20])
        #expect(hits.first?.text == "Fiyat ne kadar?")
    }

    @Test func everyTermMustAppearInTheLine() {
        let hits = TranscriptSearch.hits(in: transcript(["Pazartesi arayacağım", "Pazartesi demo", "demo hazır"]), query: "pazartesi demo")
        #expect(hits.map(\.text) == ["Pazartesi demo"])
    }

    @Test func emptyQueryHasNoHits() {
        #expect(TranscriptSearch.hits(in: transcript(["a"]), query: " ").isEmpty)
    }
}
