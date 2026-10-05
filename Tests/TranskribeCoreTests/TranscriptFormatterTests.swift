import Testing
@testable import TranskribeCore

@Suite struct TranscriptFormatterTests {
    @Test func formatsShortTimestamps() {
        #expect(TranscriptFormatter.timestamp(0) == "0:00")
        #expect(TranscriptFormatter.timestamp(65.9) == "1:05")
        #expect(TranscriptFormatter.timestamp(3_725) == "1:02:05")
    }

    @Test func formatsSRTTimestamps() {
        #expect(TranscriptFormatter.srtTimestamp(0) == "00:00:00,000")
        #expect(TranscriptFormatter.srtTimestamp(3_725.5) == "01:02:05,500")
    }

    @Test func plainTextJoinsTrimmedSegments() {
        let transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 1, text: "  Hello "),
            Segment(start: 1, end: 2, text: "world."),
        ])
        #expect(TranscriptFormatter.plainText(transcript) == "Hello world.")
    }

    @Test func plainTextBreaksParagraphOnSpeakerChange() {
        let transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 1, text: "Hi there.", speaker: SpeakerID.me),
            Segment(start: 1, end: 2, text: "How are you?", speaker: SpeakerID.me),
            Segment(start: 2, end: 3, text: "Good!", speaker: 1),
        ])
        #expect(TranscriptFormatter.plainText(transcript) == "Me: Hi there. How are you?\n\nSpeaker 1: Good!")
    }

    @Test func usesCustomSpeakerNamesInExports() {
        var transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 1, text: "Selam.", speaker: 1),
            Segment(start: 1, end: 2, text: "Merhaba.", speaker: 2),
        ])
        transcript.speakerNames = [1: "Ayşe", 2: "Mehmet"]
        #expect(TranscriptFormatter.plainText(transcript) == "Ayşe: Selam.\n\nMehmet: Merhaba.")
        #expect(TranscriptFormatter.srt(transcript).contains("Ayşe: Selam."))
        #expect(TranscriptFormatter.markdown(transcript).contains("*Mehmet* Merhaba."))
    }

    @Test func srtNumbersCues() {
        let srt = TranscriptFormatter.srt(Fixtures.transcript())
        #expect(srt == """
        1
        00:00:00,000 --> 00:00:02,500
        Merhaba, nasılsın?

        2
        00:00:02,500 --> 00:01:05,250
        İyiyim, teşekkürler.

        """)
    }

    @Test func markdownIncludesTitleAndTimestamps() {
        let markdown = TranscriptFormatter.markdown(Fixtures.transcript())
        #expect(markdown.hasPrefix("# Weekly sync\n"))
        #expect(markdown.contains("**[0:00]** Merhaba, nasılsın?"))
        #expect(markdown.contains("**[0:02]** İyiyim, teşekkürler."))
    }

    @Test func skipsEmptySegments() {
        let transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 1, text: "   "),
            Segment(start: 1, end: 2, text: "Real text"),
        ])
        #expect(TranscriptFormatter.srt(transcript).hasPrefix("1\n00:00:01,000"))
        #expect(TranscriptFormatter.plainText(transcript) == "Real text")
    }
}
