import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TranscriptMetricsTests {
    private func line(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> RawSegment {
        RawSegment(start: start, end: end, text: text)
    }

    @Test func findsLongStretchesWithoutText() {
        let segments = [line(0, 10, "Merhaba"), line(40, 50, "Nasılsın"), line(52, 60, " ")]
        #expect(TranscriptMetrics.silentStretches(segments, duration: 100) == [10.0..<40.0, 50.0..<100.0])
    }

    @Test func shortPausesAreNotStretches() {
        #expect(TranscriptMetrics.silentStretches([line(0, 10, "a"), line(15, 30, "b")], duration: 35).isEmpty)
    }

    @Test func flagsAnotherLanguagesSpelling() {
        let lines = [line(0, 1, "Eða við tað bildin kaffanða"), line(1, 2, "Açabilirim, açıyorum, açtım."),
                     line(2, 3, "Italian sports writer"), line(3, 4, "Perché no?")]
        let garbled = TranscriptMetrics.garbledLines(lines, languages: ["tr", "en", "it"])
        #expect(garbled.map(\.text) == ["Eða við tað bildin kaffanða"])
    }

    @Test func unknownLanguagesAreNotChecked() {
        #expect(TranscriptMetrics.garbledLines([line(0, 1, "こんにちは")], languages: ["ja"]).isEmpty)
    }

    @Test func wordErrorRateCountsEveryKindOfMistake() {
        #expect(TranscriptMetrics.wordErrorRate(reference: "bu adam çok ünlü", hypothesis: "bu adam çok ünlü") == 0)
        // One substitution, one deletion over four words.
        #expect(TranscriptMetrics.wordErrorRate(reference: "bu adam çok ünlü", hypothesis: "bu adım ünlü") == 0.5)
        // Case, punctuation and accents don't count.
        #expect(TranscriptMetrics.wordErrorRate(reference: "Çok ünlü.", hypothesis: "cok unlu") == 0)
    }
}
