import Foundation
import Testing
@testable import TranskribeCore

private func words(_ items: [(Double, Double, String)]) -> [Word] {
    items.map { Word(start: $0.0, end: $0.1, text: " " + $0.2) }
}

@Suite struct InterleaverTests {
    // "şu şekilde. Bu bir maaş bordrosu. Ses derinden mi geliyor bana? Bir konuşabilir misiniz?"
    let them = Segment(start: 20.2, end: 28.8, text: "", speaker: 1, words: words([
        (20.2, 20.5, "şu"), (20.5, 20.8, "şekilde."), (21.0, 21.2, "Bu"), (21.2, 21.4, "bir"), (21.4, 21.8, "maaş"),
        (21.8, 22.4, "bordrosu."), (24.8, 25.1, "Ses"), (25.1, 25.5, "derinden"), (25.5, 25.6, "mi"), (25.6, 25.9, "geliyor"),
        (25.9, 26.1, "bana?"), (27.5, 27.7, "Bir"), (27.7, 28.3, "konuşabilir"), (28.3, 28.8, "misiniz?"),
    ]))
    let reply = Segment(start: 26.6, end: 29.0, text: "Yok. Selam. 1-2-3. Denemem.", speaker: 0,
                        words: words([(26.6, 27.0, "Yok."), (27.0, 27.5, "Selam."), (27.6, 28.4, "1-2-3."), (28.4, 29.0, "Denemem.")]))

    @Test func splitsLongTurnAtTheSentenceWhereTheOtherPersonCutIn() {
        let result = Interleaver.interleave([them, reply])
        #expect(result.map(\.speaker) == [1, 0, 1])
        #expect(result[0].text.hasSuffix("bana?"))
        #expect(result[2].text == "Bir konuşabilir misiniz?")
    }

    @Test func doesNotSplitForShortReactions() {
        let okey = Segment(start: 20.9, end: 21.1, text: "Okey.", speaker: 0, words: words([(20.9, 21.1, "Okey.")]))
        #expect(Interleaver.interleave([them, okey]).filter { $0.speaker == 1 }.count == 1)
    }

    @Test func neverSplitsMidSentence() {
        let noPunctuation = Segment(start: 0, end: 10, text: "", speaker: 1, words: words((0..<10).map { (Double($0), Double($0) + 0.9, "kelime") }))
        let cut = Segment(start: 5, end: 7, text: "Ben de öyle düşünüyorum", speaker: 0, words: words([(5, 7, "Ben de öyle düşünüyorum")]))
        #expect(Interleaver.interleave([noPunctuation, cut]).filter { $0.speaker == 1 }.count == 1)
    }

    @Test func keepsAllWords() {
        let result = Interleaver.interleave([them, reply])
        #expect(result.filter { $0.speaker == 1 }.flatMap(\.words).count == them.words.count)
    }
}

@Suite struct ReactionTests {
    @Test func recognizesReactionsInAllThreeLanguages() {
        #expect(Reaction.Kind.classify("Esatto!") == .exactly)
        #expect(Reaction.Kind.classify("Aynen.") == .exactly)
        #expect(Reaction.Kind.classify("Exactly") == .exactly)
        #expect(Reaction.Kind.classify("Evet evet") == .agree)
        #expect(Reaction.Kind.classify("Sì") == .agree)
        #expect(Reaction.Kind.classify("Tamam.") == .ok)
        #expect(Reaction.Kind.classify("Va bene") == .ok)
        #expect(Reaction.Kind.classify("Hahaha") == .laugh)
        #expect(Reaction.Kind.classify("Davvero?") == .wow)
        #expect(Reaction.Kind.classify("Hmm.") == .thinking)
        #expect(Reaction.Kind.classify("Perfetto!") == .love)
    }

    @Test func realSentencesAreNotReactions() {
        #expect(Reaction.Kind.classify("Evet, Pazartesi arayacağım.") == nil)
        #expect(Reaction.Kind.classify("Tamam ama fiyat ne kadar?") == nil)
        #expect(Reaction.Kind.classify("") == nil)
    }
}

@Suite struct ReactionLayoutTests {
    private func segment(_ start: Double, _ end: Double, _ text: String, _ speaker: Int) -> Segment {
        Segment(start: start, end: end, text: text, speaker: speaker)
    }

    private func bubbles(_ items: [ChatLayout.Item]) -> [ChatLayout.Bubble] {
        items.compactMap { if case .bubble(let bubble) = $0 { bubble } else { nil } }
    }

    @Test func reactionDuringSomeoneElsesTurnBecomesATapback() {
        let items = ChatLayout.items(for: [
            segment(20, 28, "Bu bir maaş bordrosu, ses derinden mi geliyor?", 1),
            segment(22, 22.4, "Aynen.", 0),
        ], me: 0)
        let result = bubbles(items)
        #expect(result.count == 1)
        #expect(result[0].reactions.map(\.kind) == [.exactly])
        #expect(result[0].reactions.first?.speaker == 0)
    }

    @Test func reactionRightAfterATurnAttachesToIt() {
        let result = bubbles(ChatLayout.items(for: [
            segment(0, 5, "Pazartesi saat onda arayacağım.", 1),
            segment(5.6, 6, "Tamam.", 0),
        ], me: 0))
        #expect(result.count == 1)
        #expect(result[0].reactions.map(\.kind) == [.ok])
    }

    @Test func standaloneAnswerStaysAMessage() {
        // A "Yes." long after anything else is an answer, not a reaction.
        let result = bubbles(ChatLayout.items(for: [
            segment(0, 5, "Demoyu görmek ister misiniz?", 1),
            segment(12, 12.5, "Evet.", 0),
        ], me: 0))
        #expect(result.count == 2)
    }

    @Test func singleSpeakerTranscriptsKeepEverything() {
        let result = bubbles(ChatLayout.items(for: [segment(0, 3, "Bir şey söyledim.", 1), segment(3.2, 3.5, "Tamam.", 1)], me: nil))
        #expect(result.flatMap(\.reactions).isEmpty)
    }
}

@Suite struct EchoDetectorTests {
    /// Speech-like bursts: noise shaped by a syllable-rate envelope.
    private func speechLike(seconds: Double, seed: UInt64) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        let count = Int(seconds * 16_000)
        return (0..<count).map { index in
            let envelope = Float(max(0, sin(Double(index) / 16_000 * 2 * .pi * (3 + Double(seed % 3)))))
            return envelope * Float.random(in: -0.5...0.5, using: &generator)
        }
    }

    @Test func recognizesSpeakerBleedInTheMicrophone() {
        let system = speechLike(seconds: 3, seed: 1)
        let delay = 16_000 * 80 / 1000
        var noise = SeededGenerator(seed: 9)
        let mic = (0..<system.count).map { index in
            (index >= delay ? 0.3 * system[index - delay] : 0) + Float.random(in: -0.01...0.01, using: &noise)
        }
        #expect(EchoDetector.isBleed(mic: mic, system: system))
    }

    @Test func realOverlappingSpeechIsNotBleed() {
        #expect(!EchoDetector.isBleed(mic: speechLike(seconds: 3, seed: 2), system: speechLike(seconds: 3, seed: 1)))
    }

    @Test func silentSystemMeansNoBleed() {
        #expect(!EchoDetector.isBleed(mic: speechLike(seconds: 2, seed: 2), system: [Float](repeating: 0, count: 32_000)))
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
