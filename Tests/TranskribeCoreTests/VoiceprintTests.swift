import Foundation
import Testing
@testable import TranskribeCore

@Suite struct VoiceprintTests {
    private func unit(_ values: [Float]) -> [Float] { Voiceprint.normalized(values) }

    @Test func similarityOfIdenticalAndOrthogonalVoices() {
        #expect(abs(Voiceprint.similarity(unit([1, 0, 0]), unit([1, 0, 0])) - 1) < 0.0001)
        #expect(abs(Voiceprint.similarity(unit([1, 0, 0]), unit([0, 1, 0]))) < 0.0001)
        #expect(Voiceprint.similarity([1, 0], [1, 0, 0]) == 0) // mismatched sizes never match
    }

    @Test func learningAveragesWithWhatWasHeardBefore() {
        let learned = Voiceprint.merge(unit([1, 0]), weight: 3, with: unit([0, 1]))
        // Three earlier samples outweigh one new one.
        #expect(learned[0] > learned[1])
        #expect(abs(sqrt(learned.map { $0 * $0 }.reduce(0, +)) - 1) < 0.0001)
        #expect(Voiceprint.merge(nil, weight: 0, with: unit([0, 2])) == unit([0, 1]))
    }

    @Test func matchesEachVoiceToAtMostOnePerson() {
        let hakan = UUID(), ayse = UUID()
        let voices: [Int: [Float]] = [1: unit([1, 0.1, 0]), 2: unit([0.05, 1, 0]), 3: unit([0, 0, 1])]
        let people = [(id: hakan, voiceprint: unit([1, 0, 0])), (id: ayse, voiceprint: unit([0, 1, 0]))]
        let matches = VoiceMatcher.match(voices: voices, people: people)
        #expect(matches == [1: hakan, 2: ayse]) // speaker 3 sounds like nobody known
    }

    @Test func ambiguousMatchesAreLeftAlone() {
        let a = UUID(), b = UUID()
        let voices: [Int: [Float]] = [1: unit([1, 1, 0])]
        let people = [(id: a, voiceprint: unit([1, 0.95, 0])), (id: b, voiceprint: unit([0.95, 1, 0]))]
        #expect(VoiceMatcher.match(voices: voices, people: people).isEmpty)
    }

    @Test func twoVoicesNeverClaimTheSamePerson() {
        let hakan = UUID()
        let voices: [Int: [Float]] = [1: unit([1, 0.2]), 2: unit([1, 0.1])]
        let matches = VoiceMatcher.match(voices: voices, people: [(id: hakan, voiceprint: unit([1, 0]))])
        #expect(matches == [2: hakan])
    }

    @Test func picksClearSoloStretchesOfASpeaker() {
        let segments = [
            Segment(start: 0, end: 1, text: "short", speaker: 1),
            Segment(start: 1, end: 8, text: "long", speaker: 1),
            Segment(start: 7.5, end: 9, text: "overlap", speaker: 2),
            Segment(start: 10, end: 30, text: "very long", speaker: 1),
            Segment(start: 31, end: 35, text: "other", speaker: 2),
        ]
        let clips = VoiceClips.ranges(for: 1, in: segments)
        // Longest first, trimmed to 10 s, overlap with speaker 2 cut away, too-short skipped.
        #expect(clips.first.map { $0.end - $0.start } == 10)
        #expect(clips.contains { $0.start == 1 && $0.end == 7.5 })
        #expect(!clips.contains { $0.start == 0 })
    }
}
