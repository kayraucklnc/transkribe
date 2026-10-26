import Foundation
import Testing
@testable import TranskribeCore

@Suite struct LiveTrackProgressTests {
    @Test(arguments: [false, true])
    func mappingPreservesTrackProgress(hasMetadata: Bool) {
        let committed = [RawSegment(start: 2, end: 5, text: "Committed text",
                                    words: [Word(start: 2, end: 3, text: "Committed")], speaker: 1)]
        let pending = [RawSegment(start: 7, end: 9, text: "Pending text",
                                  words: [Word(start: 7, end: 8, text: "Pending")], speaker: 2)]
        let turns = [SpeakerTurn(start: 2, end: 6, speaker: 1), SpeakerTurn(start: 7, end: 10, speaker: 2)]
        let progress = TrackTranscriber.Progress(
            committed: committed, pending: pending, committedUntil: 6, availableDuration: 42.5,
            turns: turns, language: hasMetadata ? "it" : nil,
            pausedReason: hasMetadata ? "Waiting for resources" : nil
        )

        let update = progress.liveTrackProgress

        #expect(update.committed == committed)
        #expect(update.pending == pending)
        #expect(update.committedUntil == 6)
        #expect(update.availableDuration == 42.5)
        #expect(update.turns == turns)
        #expect(update.language == (hasMetadata ? "it" : nil))
        #expect(update.pausedReason == (hasMetadata ? "Waiting for resources" : nil))
    }
}
