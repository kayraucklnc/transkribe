import Foundation
import Testing
@testable import TranskribeCore

@Suite struct EngineCatalogTests {
    @Test func instantIsRecommendedWhenEveryLanguageIsBuiltIn() {
        #expect(EngineCatalog.recommendedQuality(for: ["en", "it"]) == .instant)
        #expect(EngineCatalog.recommendedQuality(for: ["tr", "en"]) == .balanced)
        #expect(EngineCatalog.recommendedQuality(for: []) == .balanced)
    }

    @Test func listsLanguagesInstantCannotHear() {
        #expect(EngineCatalog.unsupportedByInstant(["tr", "en", "it"]) == ["tr"])
        #expect(EngineCatalog.unsupportedByInstant(["en"]).isEmpty)
    }

    @Test func italianAndEnglishGoToTheFastEuropeanModel() {
        #expect(EngineCatalog.usesEuropeanModel(for: "it"))
        #expect(EngineCatalog.usesEuropeanModel(for: "en"))
        #expect(!EngineCatalog.usesEuropeanModel(for: "tr"))
    }

    @Test func settingsRoundTripAndDefaults() throws {
        let defaults = UserDefaults(suiteName: "transkribe-tests-\(UUID().uuidString)")!
        #expect(TranscriptionSettings.load(from: defaults) == .default)
        var settings = TranscriptionSettings.default
        settings.languages = ["tr", "it"]
        settings.quality = .best
        settings.vocabulary = ["Flying Papers"]
        settings.completedOnboarding = true
        settings.save(to: defaults)
        #expect(TranscriptionSettings.load(from: defaults) == settings)
    }
}

@Suite struct GapFinderTests {
    @Test func findsSpeechThatProducedNoText() {
        // Speech 0–4 s (covered) and 6–9 s (no text).
        let speech = [0.0..<4.0, 6.0..<9.0]
        let segments = [RawSegment(start: 0.2, end: 3.8, text: "Merhaba")]
        #expect(GapFinder.uncovered(speech: speech, segments: segments) == [6.0..<9.0])
    }

    @Test func ignoresShortBlips() {
        #expect(GapFinder.uncovered(speech: [0.0..<0.6], segments: []).isEmpty)
    }

    @Test func partlyCoveredSpeechKeepsTheUncoveredPart() {
        let gaps = GapFinder.uncovered(speech: [0.0..<10.0], segments: [RawSegment(start: 0, end: 4, text: "a")])
        #expect(gaps.count == 1)
        #expect(abs((gaps.first?.lowerBound ?? 0) - 4) < 0.2) // a small margin around each line
        #expect(gaps.first?.upperBound == 10)
    }

    @Test func energyDetectorFindsLoudStretches() {
        let rate = 16_000
        var samples = [Float](repeating: 0.001, count: rate * 6)
        for index in (rate * 2)..<(rate * 4) { samples[index] = sin(Float(index) * 0.07) * 0.3 }
        let regions = GapFinder.speechRegions(in: samples)
        #expect(regions.count == 1)
        #expect(abs(regions[0].lowerBound - 2) < 0.15)
        #expect(abs(regions[0].upperBound - 4) < 0.15)
    }
}

@Suite struct VocabularyCorrectorTests {
    let vocabulary = ["Flying Papers", "Kayra", "apostil", "bordrosu"]

    @Test func fixesNearMisses() {
        #expect(VocabularyCorrector.correct("Flaying Papers ile ilgili arıyorum", vocabulary: vocabulary) == "Flying Papers ile ilgili arıyorum")
        #expect(VocabularyCorrector.correct("Bu bir maaş podrosu.", vocabulary: vocabulary) == "Bu bir maaş bordrosu.")
        #expect(VocabularyCorrector.correct("Benim isim Kayra.", vocabulary: vocabulary) == "Benim isim Kayra.")
    }

    @Test func leavesUnrelatedWordsAlone() {
        let text = "Kaydet ve paylaş, apartman ve bordro"
        #expect(VocabularyCorrector.correct(text, vocabulary: vocabulary) == text)
    }

    @Test func correctsWordTimingsToo() {
        let words = [Word(start: 0, end: 1, text: " maaş"), Word(start: 1, end: 2, text: " podrosu.")]
        #expect(VocabularyCorrector.correct(words: words, vocabulary: vocabulary).map(\.text) == [" maaş", " bordrosu."])
    }
}

@Suite struct EngineOutputConversionTests {
    @Test func parakeetTokensBecomeWordsAndSentences() {
        let tokens: [(String, Double, Double)] = [
            ("▁Buon", 0.0, 0.2), ("giorno", 0.2, 0.5), ("▁a", 0.6, 0.7), ("▁tutti.", 0.7, 1.1),
            ("▁Domani", 2.5, 2.9), ("▁presentiamo.", 2.9, 3.6),
        ]
        let segments = SegmentAssembly.fromTokens(tokens)
        #expect(segments.map(\.text) == ["Buongiorno a tutti.", "Domani presentiamo."])
        #expect(segments[0].words.map(\.text) == [" Buongiorno", " a", " tutti."])
        #expect(segments[1].start == 2.5)
    }

    @Test func wordRunsBecomeSegments() {
        let runs: [(String, Double, Double)] = [("Buongiorno", 0, 0.36), (" a", 0.36, 0.5), (" tutti,", 0.72, 1.0), (" domani", 1.26, 1.5)]
        let segments = SegmentAssembly.fromWordRuns(runs)
        #expect(segments.count == 1)
        #expect(segments[0].text == "Buongiorno a tutti, domani")
        #expect(segments[0].words.count == 4)
    }
}

@Suite struct HallucinationTests {
    @Test func recognizesClassicWhisperFiller() {
        #expect(Hallucinations.isHallucination("Altyazı M.K."))
        #expect(Hallucinations.isHallucination("Sottotitoli creati dalla comunità Amara.org"))
        #expect(!Hallucinations.isHallucination("Thank you for the demo, it was great."))
    }
}
