import Foundation
import Testing
@testable import TranskribeCore

@Suite struct AIPromptBuilderTests {
    private func transcript(_ segments: [Segment], names: [Int: String] = [:]) -> Transcript {
        var transcript = Fixtures.transcript(segments: segments)
        transcript.speakerNames = names
        return transcript
    }

    @Test func rendersTimestampedLinesWithSpeakerNames() {
        let t = transcript([
            Segment(start: 0, end: 2, text: " Bütçeyi konuşalım.", speaker: 1),
            Segment(start: 2.2, end: 4, text: "Hemen başlayalım.", speaker: 1),
            Segment(start: 65, end: 67, text: "Rakamlar hazır.", speaker: 2),
        ], names: [1: "Ayşe"])
        #expect(TranscriptPromptBuilder.lines(of: t) == [
            "[0:00] Ayşe: Bütçeyi konuşalım. Hemen başlayalım.",
            "[1:05] Speaker 2: Rakamlar hazır.",
        ])
    }

    @Test func omitsNamesWithoutMultipleSpeakers() {
        let t = transcript([
            Segment(start: 0, end: 2, text: "Hello there.", speaker: 1),
            Segment(start: 3725, end: 3727, text: "Much later.", speaker: 1),
        ])
        #expect(TranscriptPromptBuilder.render(t) == "[0:00] Hello there.\n[1:02:05] Much later.")
    }

    @Test func joinsSameSpeakerAcrossShortPausesButCapsLineDuration() {
        let segments = (0..<10).map { Segment(start: Double($0) * 8, end: Double($0) * 8 + 4, text: "S\($0).", speaker: 1) }
            + [Segment(start: 81, end: 82, text: "Other.", speaker: 2)]
        let lines = TranscriptPromptBuilder.lines(of: transcript(segments))
        #expect(lines.first == "[0:00] Speaker 1: S0. S1. S2. S3.")
        #expect(lines.last == "[1:21] Speaker 2: Other.")
        #expect(lines.count == 4)
    }

    @Test func skipsEmptySegments() {
        let t = transcript([Segment(start: 0, end: 1, text: "  "), Segment(start: 1, end: 2, text: "Hi")])
        #expect(TranscriptPromptBuilder.lines(of: t) == ["[0:01] Hi"])
    }

    @Test func chunksOnLineBoundariesInOrder() {
        let lines = ["aaaa", "bbbb", "cccc", "dd"]
        #expect(TranscriptPromptBuilder.chunks(lines: lines, maxCharacters: 9) == ["aaaa\nbbbb", "cccc\ndd"])
        #expect(TranscriptPromptBuilder.chunks(lines: lines, maxCharacters: 100) == ["aaaa\nbbbb\ncccc\ndd"])
    }

    @Test func splitsOverlongLineBetweenWords() {
        let chunks = TranscriptPromptBuilder.chunks(lines: ["short", "one two three four five"], maxCharacters: 10)
        #expect(chunks == ["short", "one two", "three four", "five"])
        #expect(chunks.allSatisfy { $0.count <= 10 })
    }

    @Test func hardSplitsWordsLongerThanTheLimit() {
        #expect(TranscriptPromptBuilder.chunks(lines: ["abcdefghij"], maxCharacters: 4) == ["abcd", "efgh", "ij"])
    }

    @Test func chunksOfTranscriptPreserveAllText() {
        let segments = (0..<200).map { Segment(start: Double($0) * 40, end: Double($0) * 40 + 5, text: "Sentence number \($0).", speaker: $0 % 2 + 1) }
        let t = transcript(segments)
        let chunks = TranscriptPromptBuilder.chunks(of: t, maxCharacters: 500)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 500 })
        #expect(chunks.joined(separator: "\n") == TranscriptPromptBuilder.render(t))
    }
}

@Suite struct AITimestampTests {
    @Test func parsesMinuteAndHourTimestamps() {
        let text = "Launch moved [12:34], budget at [1:02:03] and [0:05]."
        let found = AIModel.parseTimestamps(in: text)
        #expect(found.map(\.seconds) == [754, 3723, 5])
        #expect(found.map { String(text[$0.range]) } == ["[12:34]", "[1:02:03]", "[0:05]"])
    }

    @Test func ignoresInvalidAndNonTimestampBrackets() {
        let text = "See [1:75], [1:60:00], [link](x), [12:3], [abc] and [99:59]."
        #expect(AIModel.parseTimestamps(in: text).map(\.seconds) == [5999])
    }

    @Test func handlesTurkishTextAroundTimestamps() {
        let text = "Ayşe bütçeyi onayladı [03:15]; İstanbul'a gidiyoruz [3:16]."
        #expect(AIModel.parseTimestamps(in: text).map(\.seconds) == [195, 196])
    }
}

@Suite struct TimestampLinkTests {
    @Test func turnsCitationsIntoSeekLinks() {
        let linked = AIModel.linkingTimestamps(in: "Agreed on Friday [12:34] and later [1:02:03].")
        #expect(linked == "Agreed on Friday [12:34](transkribe://seek/754) and later [1:02:03](transkribe://seek/3723).")
    }

    @Test func leavesExistingLinksAlone() {
        let text = "See [12:34](https://example.com)."
        #expect(AIModel.linkingTimestamps(in: text) == text)
    }

    @Test func parsesSeekURLs() {
        #expect(AIModel.seekTime(from: URL(string: "transkribe://seek/754")!) == 754)
        #expect(AIModel.seekTime(from: URL(string: "https://example.com")!) == nil)
    }
}

@Suite struct LocalizedHeadingTests {
    @Test func turkishSummaryTemplateUsesTurkishHeadings() {
        var transcript = Fixtures.transcript()
        transcript.language = "tr"
        let prompt = Prompts.summarySystem(for: transcript, compact: false)
        #expect(prompt.contains("## Özet"))
        #expect(prompt.contains("## Yapılacaklar"))
        #expect(!prompt.contains("## Key points"))
        #expect(!prompt.contains("## TL;DR"))
    }

    @Test func englishKeepsEnglishHeadings() {
        var transcript = Fixtures.transcript()
        transcript.language = "en"
        #expect(Prompts.summarySystem(for: transcript, compact: false).contains("## Key points"))
    }
}
