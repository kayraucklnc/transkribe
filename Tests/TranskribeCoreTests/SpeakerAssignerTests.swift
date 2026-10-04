import Foundation
import Testing
@testable import TranskribeCore

@Suite struct SpeakerAssignerTests {
    private func words(_ items: [(Double, Double, String)]) -> [Word] {
        items.map { Word(start: $0.0, end: $0.1, text: $0.2) }
    }

    @Test func splitsSegmentAtSpeakerChange() {
        let segment = RawSegment(start: 0, end: 4, text: " Are you ready? Yes I am.", words: words([
            (0, 0.5, " Are"), (0.5, 0.8, " you"), (0.8, 1.5, " ready?"),
            (2, 2.4, " Yes"), (2.4, 2.6, " I"), (2.6, 3, " am."),
        ]))
        let turns = [SpeakerTurn(start: 0, end: 1.6, speaker: 1), SpeakerTurn(start: 1.9, end: 3.2, speaker: 2)]

        let result = SpeakerAssigner.assign([segment], turns: turns)

        #expect(result.map(\.text) == ["Are you ready?", "Yes I am."])
        #expect(result.map(\.speaker) == [1, 2])
        #expect(result[1].start == 2)
        #expect(result[1].end == 3)
    }

    @Test func smoothsSingleWordFlickerBetweenSameSpeaker() {
        let segment = RawSegment(start: 0, end: 3, text: "", words: words([
            (0, 0.5, " We"), (0.5, 1.0, " should"), (1.0, 1.2, " really"), (1.2, 2, " ship"), (2, 3, " it."),
        ]))
        let turns = [
            SpeakerTurn(start: 0, end: 1.0, speaker: 1),
            SpeakerTurn(start: 1.0, end: 1.25, speaker: 2),
            SpeakerTurn(start: 1.25, end: 3, speaker: 1),
        ]
        let result = SpeakerAssigner.assign([segment], turns: turns)
        #expect(result.count == 1)
        #expect(result[0].text == "We should really ship it.")
    }

    @Test func absorbsStrayEdgeWord() {
        let segment = RawSegment(start: 0, end: 3, text: "", words: words([
            (0, 0.3, " So"), (0.3, 1, " the"), (1, 2, " plan"), (2, 3, " works."),
        ]))
        let turns = [SpeakerTurn(start: 0, end: 0.31, speaker: 2), SpeakerTurn(start: 0.31, end: 3, speaker: 1)]
        let result = SpeakerAssigner.assign([segment], turns: turns)
        #expect(result.map(\.speaker) == [1])
    }

    @Test func wordsInGapsSnapToNearestTurn() {
        let segment = RawSegment(start: 0, end: 2, text: "Hello there", words: words([(0, 0.5, " Hello"), (1.6, 2, " there")]))
        let turns = [SpeakerTurn(start: 0, end: 1, speaker: 1), SpeakerTurn(start: 2.3, end: 4, speaker: 2)]

        let result = SpeakerAssigner.assign([segment], turns: turns)

        // Two single words are too little evidence to split an utterance.
        #expect(result.count == 1)
    }

    @Test func keepsShortRepliesTogether() {
        let segment = RawSegment(start: 1.9, end: 2.6, text: "Evet buyurun.", words: words([(1.9, 2.2, " Evet"), (2.2, 2.6, " buyurun.")]))
        let turns = [SpeakerTurn(start: 0, end: 2.1, speaker: 1), SpeakerTurn(start: 2.2, end: 2.8, speaker: 2)]
        let result = SpeakerAssigner.assign([segment], turns: turns)
        #expect(result.map(\.text) == ["Evet buyurun."])
        #expect(result.first?.speaker == 2)
    }

    @Test func farAwayWordsInheritPreviousSpeaker() {
        let segment = RawSegment(start: 0, end: 10, text: "a b", words: words([(0, 0.5, " a"), (8, 9, " b")]))
        let turns = [SpeakerTurn(start: 0, end: 1, speaker: 3)]

        let result = SpeakerAssigner.assign([segment], turns: turns)

        #expect(result.count == 1)
        #expect(result[0].speaker == 3)
        #expect(result[0].text == "a b")
    }

    @Test func segmentsWithoutWordsUseDominantSpeaker() {
        let segment = RawSegment(start: 0, end: 10, text: "Long monologue")
        let turns = [SpeakerTurn(start: 0, end: 2, speaker: 1), SpeakerTurn(start: 2, end: 10, speaker: 2)]

        #expect(SpeakerAssigner.assign([segment], turns: turns).first?.speaker == 2)
    }

    @Test func noTurnsLeavesSegmentsUntouched() {
        let segment = RawSegment(start: 0, end: 1, text: "Hi")
        #expect(SpeakerAssigner.assign([segment], turns: []) == [segment])
    }

    @Test func renumbersSpeakersByFirstAppearance() {
        let turns = DiarizationEngine.renumbered([
            SpeakerTurn(start: 5, end: 6, speaker: 0),
            SpeakerTurn(start: 0, end: 1, speaker: 7),
            SpeakerTurn(start: 2, end: 3, speaker: 0),
        ])
        #expect(turns.map(\.speaker) == [1, 2, 2])
    }
}

@Suite struct SpeakerStatsTests {
    @Test func computesTalkTimeShares() {
        let shares = SpeakerStats.shares(of: [
            Segment(start: 0, end: 30, text: "a", speaker: 1),
            Segment(start: 30, end: 40, text: "b", speaker: 2),
            Segment(start: 40, end: 70, text: "c", speaker: 1),
        ])
        #expect(shares.map(\.speaker) == [1, 2])
        #expect(shares[0].fraction == 60.0 / 70.0)
        #expect(shares[0].turns == 2)
        #expect(shares[1].turns == 1)
    }

    @Test func ignoresUnlabeledSegments() {
        #expect(SpeakerStats.shares(of: [Segment(start: 0, end: 5, text: "x")]).isEmpty)
    }
}

@Suite struct TranscriptSpeakerTests {
    @Test func defaultAndCustomNames() {
        var transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 1, text: "a", speaker: SpeakerID.me),
            Segment(start: 1, end: 2, text: "b", speaker: 2),
        ])
        #expect(transcript.name(of: SpeakerID.me) == "Me")
        #expect(transcript.name(of: 2) == "Speaker 1") // the first voice besides "Me"
        transcript.speakerNames[2] = "Ayşe"
        #expect(transcript.name(of: 2) == "Ayşe")
        #expect(transcript.speakers == [0, 2])
        #expect(transcript.hasSpeakers)
    }

    @Test func singleSpeakerIsNotLabeled() {
        let transcript = Fixtures.transcript(segments: [Segment(start: 0, end: 1, text: "a", speaker: 1)])
        #expect(!transcript.hasSpeakers)
    }

    @Test func decodesVersionOneFiles() throws {
        let json = """
        {"id":"7B0A3C8E-0000-4000-8000-000000000001","title":"Old","createdAt":"2026-10-04T10:00:00Z","duration":3,
         "tracks":[{"fileName":"microphone.m4a","speaker":"me","offset":0},{"fileName":"system.m4a","speaker":"others","offset":0.5}],
         "segments":[{"id":"7B0A3C8E-0000-4000-8000-000000000002","start":0,"end":1,"text":"Hi","speaker":"me"},
                     {"id":"7B0A3C8E-0000-4000-8000-000000000003","start":1,"end":2,"text":"Hello","speaker":"others"}],
         "status":{"done":{}}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(Transcript.self, from: Data(json.utf8))

        #expect(transcript.tracks.map(\.source) == [.microphone, .system])
        #expect(transcript.segments.map(\.speaker) == [SpeakerID.me, 1])
        #expect(transcript.speakerNames.isEmpty)
    }
}
