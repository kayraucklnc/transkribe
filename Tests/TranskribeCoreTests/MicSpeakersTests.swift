import Foundation
import Testing
@testable import TranskribeCore

@Suite struct MicSpeakersTests {
    private func segment(_ start: Double, _ end: Double, _ text: String = "words") -> RawSegment {
        RawSegment(start: start, end: end, text: text)
    }

    @Test func withoutTurnsEverythingIsMe() {
        let labeled = MicSpeakers.labelWithCall([segment(0, 5)], turns: [])
        #expect(labeled.map(\.speaker) == [SpeakerID.me])
    }

    @Test func whoeverTalksMostIsMeAndOthersInTheRoomGetTheirOwnNumbers() {
        let turns = [
            SpeakerTurn(start: 0, end: 60, speaker: 2),     // the user, most speech
            SpeakerTurn(start: 60, end: 90, speaker: 5),    // a colleague in the room, 30 s
            SpeakerTurn(start: 90, end: 150, speaker: 2),
        ]
        let labeled = MicSpeakers.labelWithCall([segment(0, 60), segment(61, 89), segment(91, 150)], turns: turns)
        #expect(labeled.map(\.speaker) == [SpeakerID.me, SpeakerID.firstInRoom, SpeakerID.me])
    }

    @Test func briefStrayVoicesStayMe() {
        // 6 s out of 126 s: a phantom split or a cough, not another person.
        let turns = [SpeakerTurn(start: 0, end: 60, speaker: 1), SpeakerTurn(start: 60, end: 66, speaker: 3),
                     SpeakerTurn(start: 66, end: 126, speaker: 1)]
        let labeled = MicSpeakers.labelWithCall([segment(0, 60), segment(60, 66), segment(66, 126)], turns: turns)
        #expect(labeled.allSatisfy { $0.speaker == SpeakerID.me })
    }

    @Test func roomSpeakersAreNumberedInOrderOfAppearance() {
        let turns = [SpeakerTurn(start: 0, end: 100, speaker: 1), SpeakerTurn(start: 100, end: 130, speaker: 4),
                     SpeakerTurn(start: 130, end: 160, speaker: 2)]
        let labeled = MicSpeakers.labelWithCall([segment(0, 100), segment(100, 130), segment(130, 160)], turns: turns)
        #expect(labeled.map(\.speaker) == [SpeakerID.me, SpeakerID.firstInRoom, SpeakerID.firstInRoom + 1])
    }

    @Test func micOnlyWithOneVoiceIsMe() {
        let turns = [SpeakerTurn(start: 0, end: 30, speaker: 1)]
        #expect(MicSpeakers.labelAlone([segment(0, 30)], turns: turns).map(\.speaker) == [SpeakerID.me])
        #expect(MicSpeakers.labelAlone([segment(0, 30)], turns: []).map(\.speaker) == [SpeakerID.me])
    }

    @Test func micOnlyWithSeveralVoicesKeepsThemApart() {
        let turns = [SpeakerTurn(start: 0, end: 30, speaker: 1), SpeakerTurn(start: 30, end: 60, speaker: 2)]
        let labeled = MicSpeakers.labelAlone([segment(0, 30), segment(30, 60)], turns: turns)
        #expect(labeled.map(\.speaker) == [1, 2])
    }

    @Test func defaultNamesCountPeopleNotInternalNumbers() {
        var transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 1, text: "a", speaker: SpeakerID.me),
            Segment(start: 1, end: 2, text: "b", speaker: 3),
            Segment(start: 2, end: 3, text: "c", speaker: SpeakerID.firstInRoom),
        ])
        transcript.speakerNames = [:]
        #expect(transcript.name(of: 3) == "Speaker 1")
        #expect(transcript.name(of: SpeakerID.firstInRoom) == "Speaker 2")
        #expect(transcript.name(of: SpeakerID.me) == "Me")
    }
}
