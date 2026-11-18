import Foundation
import Testing
@testable import TranskribeCore

@Suite struct VoiceSeparatorTests {
    /// A made-up voiceprint: mostly along `voice`'s own axis, with a little of the others.
    private func print(_ voice: Int, wobble: Int = 0) -> [Float] {
        Voiceprint.normalized((0..<8).map { axis in axis == voice ? 1 : Float((axis + wobble) % 3) * 0.05 })
    }

    /// Turns and one voiceprint per window, where `voices[i]` is who really talks in turn `i`
    /// (nil: too short for a voiceprint).
    private func separate(_ turns: [SpeakerTurn], voices: (SpeakerTurn) -> Int?, speakerCount: Int? = nil) -> [SpeakerTurn] {
        let windows = VoiceSeparator.windows(for: turns)
        let prints = windows.enumerated().map { index, window -> [Float]? in
            guard window.wantsVoiceprint, let turn = turns.first(where: { $0.start <= window.start && window.end <= $0.end }),
                  let voice = voices(turn) else { return nil }
            return print(voice, wobble: index)
        }
        return VoiceSeparator.separate(turns: turns, windows: windows, voiceprints: prints, speakerCount: speakerCount)
    }

    private func speaker(at time: TimeInterval, in turns: [SpeakerTurn]) -> Int? {
        turns.first { $0.start <= time && time < $0.end }?.speaker
    }

    // MARK: - Windows

    @Test func cutsTurnsIntoWindowsOfAboutThreeSeconds() {
        let windows = VoiceSeparator.windows(for: [SpeakerTurn(start: 0, end: 9, speaker: 1)])
        #expect(windows.count == 3)
        #expect(windows.map(\.start) == [0, 3, 6])
        #expect(windows.last?.end == 9)
        #expect(Set(windows.map(\.piece)).count == 1)
    }

    @Test func keepsOverlapAsItsOwnWindow() {
        let windows = VoiceSeparator.windows(for: [
            SpeakerTurn(start: 0, end: 4, speaker: 1), SpeakerTurn(start: 3, end: 7, speaker: 2),
        ])
        #expect(windows.map(\.slots) == [[1], [1, 2], [2]])
        #expect(windows[1].start == 3 && windows[1].end == 4)
        #expect(!windows[1].wantsVoiceprint)
    }

    // MARK: - Separating voices

    @Test func splitsOneSlotHoldingSeveralPeople() {
        // The speaker model puts three people of a meeting in slot 1 and one in slot 2.
        var turns: [SpeakerTurn] = []
        var people: [Int] = []
        for index in 0..<12 {
            turns.append(SpeakerTurn(start: Double(index) * 7, end: Double(index) * 7 + 6, speaker: index % 4 == 3 ? 2 : 1))
            people.append(index % 4)
        }
        let result = separate(turns) { turn in people[turns.firstIndex(of: turn)!] }

        #expect(Set(result.map(\.speaker)).count == 4)
        for (turn, person) in zip(turns, people) {
            let first = turns[people.firstIndex(of: person)!]
            #expect(speaker(at: turn.start + 3, in: result) == speaker(at: first.start + 3, in: result))
        }
    }

    @Test func joinsOnePersonTheModelSplitAcrossSlots() {
        let turns = (0..<8).map { SpeakerTurn(start: Double($0) * 7, end: Double($0) * 7 + 6, speaker: $0 % 2 + 1) }
        let result = separate(turns) { _ in 0 }
        #expect(Set(result.map(\.speaker)) == [1])
    }

    @Test func keepsTheNumberOfPeopleTheUserChose() {
        let turns = (0..<9).map { SpeakerTurn(start: Double($0) * 7, end: Double($0) * 7 + 6, speaker: 1) }
        let result = separate(turns, voices: { turns.firstIndex(of: $0)! % 3 }, speakerCount: 2)
        #expect(Set(result.map(\.speaker)).count == 2)
    }

    @Test func foldsAStrayVoiceIntoTheClosestRealOne() {
        // Voice 2 only has two seconds: a cough or a phantom, not a person.
        var turns = (0..<6).map { SpeakerTurn(start: Double($0) * 7, end: Double($0) * 7 + 6, speaker: $0 % 2 + 1) }
        turns.append(SpeakerTurn(start: 50, end: 52, speaker: 3))
        let result = separate(turns) { turn in turn.speaker == 3 ? 2 : turn.speaker - 1 }
        #expect(Set(result.map(\.speaker)).count == 2)
    }

    @Test func shortWordsFollowTheVoiceAroundThem() {
        // A 0.4 s "evet" from the same slot right after a long turn has no voiceprint of its own.
        let turns = [
            SpeakerTurn(start: 0, end: 6, speaker: 1), SpeakerTurn(start: 7, end: 13, speaker: 2),
            SpeakerTurn(start: 13.2, end: 13.6, speaker: 2), SpeakerTurn(start: 15, end: 21, speaker: 1),
        ]
        let result = separate(turns) { turn in turn.end - turn.start < 1 ? nil : turn.speaker - 1 }
        #expect(speaker(at: 13.4, in: result) == speaker(at: 10, in: result))
        #expect(speaker(at: 13.4, in: result) != speaker(at: 3, in: result))
    }

    @Test func leavesTurnsAloneWithoutVoiceprints() {
        let turns = [SpeakerTurn(start: 0, end: 6, speaker: 1), SpeakerTurn(start: 7, end: 13, speaker: 2)]
        let windows = VoiceSeparator.windows(for: turns)
        let result = VoiceSeparator.separate(turns: turns, windows: windows, voiceprints: windows.map { _ in nil })
        #expect(result == turns)
    }

    // MARK: - Building blocks

    @Test func averageLinkageStopsAtTheThreshold() {
        let vectors = [print(0), print(0, wobble: 1), print(1), print(1, wobble: 2), print(2)]
        let labels = Clustering.averageLinkage(vectors, threshold: 0.5)
        #expect(labels[0] == labels[1])
        #expect(labels[2] == labels[3])
        #expect(Set(labels).count == 3)
        #expect(Set(Clustering.averageLinkage(vectors, threshold: 0.5, count: 2)).count == 2)
    }

    @Test func pathOnlyChangesVoiceWhenItPays() {
        // One slightly-better window for voice 1 inside a run of voice 0 isn't worth two changes.
        let evidence: [[Float]] = [[0.6, 0.1], [0.6, 0.1], [0.35, 0.4], [0.6, 0.1]]
        #expect(VoiceSeparator.path(evidence: evidence) { _ in 0.1 } == [0, 0, 0, 0])
        #expect(VoiceSeparator.path(evidence: evidence) { _ in 0 } == [0, 0, 1, 0])
    }
}
