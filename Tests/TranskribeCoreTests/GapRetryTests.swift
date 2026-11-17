import Foundation
import Testing
@testable import TranskribeCore

/// A Turkish call lost a third of its text: Whisper returned lines without words over real speech,
/// those lines hid the speech from the retry, and the retry redid it in scraps without context.
@Suite struct GapRetryTests {
    @Test func aLineWithoutWordsDoesNotHideSpeech() {
        let speech = [0.0..<27.0]
        let blank = RawSegment(start: 0, end: 27.2, text: " ")
        #expect(GapFinder.uncovered(speech: speech, segments: [blank]) == [0.0..<27.0])
    }

    @Test func nearbyGapsAreRetriedTogether() {
        let gaps = [1.0..<3.0, 3.5..<6.0, 7.0..<9.0]
        #expect(GapFinder.retrySpans(gaps) == [1.0..<9.0])
    }

    @Test func distantGapsStaySeparate() {
        #expect(GapFinder.retrySpans([1.0..<3.0, 10.0..<12.0]) == [1.0..<3.0, 10.0..<12.0])
    }

    @Test func retriesFitOneWindow() {
        let spans = GapFinder.retrySpans([0.0..<20.0, 21.0..<40.0])
        #expect(spans.allSatisfy { $0.upperBound - $0.lowerBound <= GapFinder.longestRetry })
        #expect(spans.first?.lowerBound == 0)
        #expect(spans.last?.upperBound == 40)
    }

    @Test func aLongDroppedStretchIsSplitIntoWindows() {
        #expect(GapFinder.retrySpans([0.0..<64.0]) == [0.0..<28.0, 28.0..<56.0, 56.0..<64.0])
    }

    @Test func cleaningDropsLinesWithoutWords() {
        let segments = [RawSegment(start: 0, end: 27, text: ""), RawSegment(start: 27, end: 30, text: " Çok ünlü.")]
        #expect(GapFinder.cleaned(segments, duration: 35).map(\.text) == [" Çok ünlü."])
    }

    @Test func cleaningKeepsTimesInsideTheClip() {
        let late = RawSegment(start: 30, end: 55.7, text: " Nereden biliyor kanka?",
                              words: [Word(start: 54, end: 55.7, text: " kanka?")])
        let outside = RawSegment(start: 36, end: 37, text: " Evet.")
        let cleaned = GapFinder.cleaned([late, outside], duration: 35)
        #expect(cleaned.count == 1)
        #expect(cleaned[0].end == 35)
        #expect(cleaned[0].words.allSatisfy { $0.end <= 35 && $0.start <= 35 })
    }
}
