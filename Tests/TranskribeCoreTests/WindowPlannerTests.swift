import Foundation
import Testing
@testable import TranskribeCore

@Suite struct WindowPlannerTests {
    let planner = WindowPlanner(minimumWindow: 30, maximumWindow: 120, tailGuard: 5)

    private func segment(_ start: Double, _ end: Double, _ text: String = "x") -> RawSegment {
        RawSegment(start: start, end: end, text: text, words: [Word(start: start, end: end, text: " " + text)])
    }

    @Test func waitsForEnoughLiveAudio() {
        #expect(planner.window(committed: 0, available: 20, sourceComplete: false) == nil)
        #expect(planner.window(committed: 0, available: 31, sourceComplete: false) == .init(start: 0, end: 31, isFinal: false))
    }

    @Test func capsWindowLength() {
        #expect(planner.window(committed: 10, available: 500, sourceComplete: true) == .init(start: 10, end: 130, isFinal: false))
    }

    @Test func finalWindowCoversTheRestOfACompleteSource() {
        #expect(planner.window(committed: 100, available: 112, sourceComplete: true) == .init(start: 100, end: 112, isFinal: true))
        #expect(planner.window(committed: 112, available: 112, sourceComplete: true) == nil)
    }

    @Test func holdsBackSegmentsNearTheEdge() {
        let window = WindowPlanner.Window(start: 0, end: 40, isFinal: false)
        let result = planner.commit([segment(0, 10), segment(10, 33), segment(33, 39)], in: window)
        #expect(result.segments.map(\.end) == [10, 33])
        #expect(result.committedUntil == 33)
    }

    @Test func nextWindowStartsExactlyWhereCommittedTextEnds() {
        let first = planner.commit([segment(0, 12), segment(12, 37)], in: .init(start: 0, end: 40, isFinal: false))
        let next = planner.window(committed: first.committedUntil, available: 80, sourceComplete: false)
        #expect(first.committedUntil == 12)
        #expect(next?.start == 12)
    }

    @Test func finalWindowCommitsEverything() {
        let result = planner.commit([segment(100, 108), segment(108, 111.9)], in: .init(start: 100, end: 112, isFinal: true))
        #expect(result.segments.count == 2)
        #expect(result.committedUntil == 112)
    }

    @Test func silenceAdvancesToTheGuard() {
        let result = planner.commit([], in: .init(start: 0, end: 40, isFinal: false))
        #expect(result.committedUntil == 35)
    }

    @Test func longSegmentPastTheGuardWaits() {
        let result = planner.commit([segment(2, 38)], in: .init(start: 0, end: 40, isFinal: false))
        #expect(result.segments.isEmpty)
        #expect(result.committedUntil == 0)
    }

    @Test func fullWindowWithoutCommitStillMovesForward() {
        // A maximum-length window must always make progress, or a stuck segment would loop forever.
        let result = planner.commit([segment(1, 118)], in: .init(start: 0, end: 120, isFinal: false))
        #expect(result.segments.count == 1)
        #expect(result.committedUntil == 118)
    }

    @Test func dropsRepeatedSegmentAtBatchSeam() {
        let previous = segment(5, 12, "Evet buyurun.")
        let result = planner.commit([segment(12, 12.6, "Evet buyurun."), segment(13, 20, "Kolay gelsin.")],
                                    in: .init(start: 12, end: 50, isFinal: false), previous: previous)
        #expect(result.segments.map(\.text) == ["Kolay gelsin."])
    }
}

@Suite struct PCMStoreTests {
    @Test func appendsAndReadsRanges() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("live.pcm")
        let writer = try PCMStore.Writer(url: url)
        try writer.append((0..<32_000).map { Float($0 % 100) / 100 })
        try writer.append([Float](repeating: 0.5, count: 16_000))

        let reader = PCMStore.Reader(url: url)
        #expect(abs(reader.duration - 3) < 0.001)
        let slice = try reader.read(from: 1, to: 1.5)
        #expect(slice.count == 8_000)
        #expect(abs(slice[0] - 0.0) < 0.001)   // sample 16000 → 16000 % 100 = 0
        let tail = try reader.read(from: 2.5, to: 10)
        #expect(tail.count == 8_000)
        #expect(abs(tail[0] - 0.5) < 0.001)
    }

    @Test func clipsOutOfRangeValues() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("clip.pcm")
        let writer = try PCMStore.Writer(url: url)
        try writer.append([2, -2])
        let samples = try PCMStore.Reader(url: url).read(from: 0, to: 1)
        #expect(samples.map { ($0 * 100).rounded() } == [100, -100])
    }

    @Test func missingFileIsEmpty() {
        let reader = PCMStore.Reader(url: URL(fileURLWithPath: "/nonexistent/x.pcm"))
        #expect(reader.duration == 0)
    }
}
