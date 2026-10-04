import Testing
@testable import TranskribeCore

@Suite struct TrackMergerTests {
    @Test func shiftsByOffsetAndSortsByStart() {
        let merged = TrackMerger.merge([
            .init(speaker: .others, offset: 0, segments: [
                RawSegment(start: 0, end: 2, text: "Hello"),
                RawSegment(start: 4, end: 5, text: "Bye"),
            ]),
            .init(speaker: .me, offset: 1.5, segments: [
                RawSegment(start: 1, end: 2, text: "Hi back"),
            ]),
        ])

        #expect(merged.map(\.text) == ["Hello", "Hi back", "Bye"])
        #expect(merged[1].start == 2.5)
        #expect(merged[1].speaker == .me)
    }

    @Test func singleTrackHasNoSpeakerLabels() {
        let merged = TrackMerger.merge([
            .init(speaker: .me, offset: 0, segments: [RawSegment(start: 0, end: 1, text: "Solo")]),
        ])
        #expect(merged.first?.speaker == nil)
    }

    @Test func dropsMicEchoOfSystemAudio() {
        let merged = TrackMerger.merge([
            .init(speaker: .others, offset: 0, segments: [
                RawSegment(start: 10, end: 14, text: "We should ship the release on Friday."),
            ]),
            .init(speaker: .me, offset: 0, segments: [
                RawSegment(start: 10.3, end: 14.2, text: "we should ship the release on friday"),
                RawSegment(start: 15, end: 16, text: "Sounds good to me."),
            ]),
        ])

        #expect(merged.map(\.text) == ["We should ship the release on Friday.", "Sounds good to me."])
    }

    @Test func keepsShortMicRepliesEvenIfWordsOverlap() {
        let merged = TrackMerger.merge([
            .init(speaker: .others, offset: 0, segments: [RawSegment(start: 0, end: 4, text: "Is that okay with you?")]),
            .init(speaker: .me, offset: 0, segments: [RawSegment(start: 3, end: 4, text: "Okay.")]),
        ])
        #expect(merged.count == 2)
    }

    @Test func keepsMicSpeechThatOnlyOverlapsInTime() {
        let merged = TrackMerger.merge([
            .init(speaker: .others, offset: 0, segments: [RawSegment(start: 0, end: 4, text: "Can you hear me?")]),
            .init(speaker: .me, offset: 0, segments: [RawSegment(start: 1, end: 3, text: "Yes, loud and clear.")]),
        ])
        #expect(merged.count == 2)
    }

    @Test func dropsBlankAndWhisperArtifactSegments() {
        let merged = TrackMerger.merge([
            .init(speaker: .me, offset: 0, segments: [
                RawSegment(start: 0, end: 1, text: "  "),
                RawSegment(start: 1, end: 2, text: "[BLANK_AUDIO]"),
                RawSegment(start: 2, end: 3, text: "<|en|> Hello <|endoftext|>"),
            ]),
        ])
        #expect(merged.map(\.text) == ["Hello"])
    }

    @Test func stripsDialogueDashes() {
        let merged = TrackMerger.merge([
            .init(speaker: nil, offset: 0, segments: [
                RawSegment(start: 0, end: 1, text: "-Aynı şeyler geliyor değil mi?"),
                RawSegment(start: 1, end: 2, text: " - Okey"),
                RawSegment(start: 2, end: 3, text: "e-posta - adresim"),
            ]),
        ])
        #expect(merged.map(\.text) == ["Aynı şeyler geliyor değil mi?", "Okey", "e-posta - adresim"])
    }

    @Test func similarityIsCaseAndPunctuationInsensitive() {
        #expect(TrackMerger.similarity("Hello, World!", "hello world") == 1)
        #expect(TrackMerger.similarity("a b", "c d") == 0)
    }
}
