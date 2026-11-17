import Foundation
import Testing
@testable import TranskribeCore

@Suite struct RecordingQualityTests {
    @Test func bestIsRecordedWithBalancedSoItKeepsUp() {
        #expect(TranscriptionQuality.best.whileRecording == .balanced)
    }

    @Test(arguments: [TranscriptionQuality.instant, .balanced])
    func fasterQualitiesRecordAsChosen(_ quality: TranscriptionQuality) {
        #expect(quality.whileRecording == quality)
    }

    @Test func aQuickRecordingOwesTheChosenQuality() {
        #expect(TranscriptionQuality.upgrade(to: .best, after: .balanced) == .best)
        #expect(TranscriptionQuality.upgrade(to: .balanced, after: .instant) == .balanced)
    }

    @Test func aGoodEnoughPassSettlesIt() {
        #expect(TranscriptionQuality.upgrade(to: .best, after: .best) == nil)
        #expect(TranscriptionQuality.upgrade(to: .balanced, after: .best) == nil)
        #expect(TranscriptionQuality.upgrade(to: nil, after: .balanced) == nil)
    }

    @Test func theOwedPassSurvivesAReopen() throws {
        var transcript = Fixtures.transcript()
        transcript.upgradeQuality = .best
        let decoded = try JSONDecoder().decode(Transcript.self, from: JSONEncoder().encode(transcript))
        #expect(decoded.upgradeQuality == .best)
    }

    @Test func olderTranscriptsOweNothing() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixtures.transcript())) as! [String: Any]
        json["upgradeQuality"] = nil
        let decoded = try JSONDecoder().decode(Transcript.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.upgradeQuality == nil)
    }
}
