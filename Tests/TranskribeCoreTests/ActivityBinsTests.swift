import Testing
@testable import TranskribeCore

@Suite struct ActivityBinsTests {
    @Test func binsSpeechDensityAndDominantSpeaker() {
        let segments = [
            Segment(start: 0, end: 10, text: "a", speaker: 1),
            Segment(start: 10, end: 15, text: "b", speaker: 2),
            Segment(start: 30, end: 40, text: "c", speaker: 2),
        ]
        let bins = ActivityBins.make(segments: segments, duration: 40, count: 4)
        #expect(bins.count == 4)
        #expect(bins[0].level == 1)            // 0–10 fully spoken
        #expect(bins[0].speaker == 1)
        #expect(bins[1].speaker == 2)          // 10–20: speaker 2 for 5 s
        #expect(abs(bins[1].level - 0.5) < 0.001)
        #expect(bins[2].level == 0)            // silence
        #expect(bins[2].speaker == nil)
        #expect(bins[3].speaker == 2)
    }

    @Test func emptyInputGivesFlatBins() {
        let bins = ActivityBins.make(segments: [], duration: 0, count: 8)
        #expect(bins.count == 8)
        #expect(bins.allSatisfy { $0.level == 0 })
    }
}
