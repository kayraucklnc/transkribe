import Testing
@testable import TranskribeCore

@Suite struct RepetitionFilterTests {
    @Test func collapsesRunawaySyllables() {
        let looped = "Sağ ol" + String(repeating: "un", count: 120)
        #expect(RepetitionFilter.collapse(looped) == "Sağ olun")
    }

    @Test func collapsesRepeatedWordsAndPhrases() {
        #expect(RepetitionFilter.collapse("Evet evet evet evet evet evet evet tamam") == "Evet tamam")
        #expect(RepetitionFilter.collapse("thank you. thank you. thank you. thank you. thank you. Bye") == "thank you. Bye")
    }

    @Test func keepsNaturalRepetition() {
        let natural = ["Evet evet, tamam.", "Hahaha that's funny", "No no no, wait.", "www.example.com", "1000000 lira"]
        for text in natural {
            #expect(RepetitionFilter.collapse(text) == text)
        }
    }

    @Test func mergerAppliesFilter() {
        let merged = TrackMerger.merge([.init(source: nil, offset: 0, segments: [
            RawSegment(start: 0, end: 1, text: "Sağ ol" + String(repeating: "un", count: 50)),
        ])])
        #expect(merged.first?.text == "Sağ olun")
    }
}

@Suite struct SignificantSpeakerTests {
    @Test func ignoresPhantomSpeakers() {
        let turns = [
            SpeakerTurn(start: 0, end: 464, speaker: 1),
            SpeakerTurn(start: 464, end: 481, speaker: 2),
            SpeakerTurn(start: 481, end: 485, speaker: 3),
            SpeakerTurn(start: 485, end: 572, speaker: 4),
        ]
        #expect(DiarizationEngine.significantSpeakerCount(turns) == 2)
    }

    @Test func keepsBalancedSpeakers() {
        let turns = [SpeakerTurn(start: 0, end: 10, speaker: 1), SpeakerTurn(start: 10, end: 18, speaker: 2)]
        #expect(DiarizationEngine.significantSpeakerCount(turns) == 2)
    }

    @Test func keepsTheRequestedNumberOfMostTalkativeSpeakers() {
        let turns = [
            SpeakerTurn(start: 0, end: 10, speaker: 1),
            SpeakerTurn(start: 10, end: 12, speaker: 2),
            SpeakerTurn(start: 12, end: 20, speaker: 3),
        ]
        #expect(DiarizationEngine.select(turns, speakerCount: 2).map(\.speaker) == [1, 3])
        #expect(DiarizationEngine.select(turns, speakerCount: nil).map(\.speaker) == [1, 2, 3])
        #expect(DiarizationEngine.select(turns, speakerCount: 5).count == 3)
    }

    @Test func automaticModeDropsPhantoms() {
        let turns = [
            SpeakerTurn(start: 0, end: 437, speaker: 0),
            SpeakerTurn(start: 437, end: 596, speaker: 1),
            SpeakerTurn(start: 596, end: 611, speaker: 2),
        ]
        #expect(Set(DiarizationEngine.select(turns, speakerCount: nil).map(\.speaker)) == [0, 1])
    }

    @Test func treatsSmallThirdVoiceAsNoise() {
        let turns = [
            SpeakerTurn(start: 0, end: 475, speaker: 0),
            SpeakerTurn(start: 475, end: 592, speaker: 1),
            SpeakerTurn(start: 592, end: 625, speaker: 2),
        ]
        #expect(DiarizationEngine.significantSpeakerCount(turns) == 2)
    }

    @Test func atLeastOne() {
        #expect(DiarizationEngine.significantSpeakerCount([]) == 1)
    }
}
