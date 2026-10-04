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
