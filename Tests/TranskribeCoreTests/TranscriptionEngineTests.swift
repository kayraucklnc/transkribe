import Testing
@testable import TranskribeCore

@Suite struct TranscriptionEngineTests {
    @Test func picksMostFrequentLanguage() {
        #expect(TranscriptionEngine.dominantLanguage(["tr", "en", "tr"]) == "tr")
    }

    @Test func ignoresEmptyLanguages() {
        #expect(TranscriptionEngine.dominantLanguage(["", ""]) == nil)
        #expect(TranscriptionEngine.dominantLanguage([]) == nil)
    }

    @Test func breaksTiesDeterministically() {
        #expect(TranscriptionEngine.dominantLanguage(["en", "tr"]) == "en")
    }
}

@Suite struct WeightedLanguageTests {
    @Test func mostSpokenTextWinsOverMostChunks() {
        // Many short (often silent) chunks guessed as English, one long Turkish stretch.
        let weights = ["en": 40, "tr": 2_400]
        #expect(TranscriptionEngine.dominantLanguage(weights: weights) == "tr")
    }

    @Test func emptyWeightsHaveNoLanguage() {
        #expect(TranscriptionEngine.dominantLanguage(weights: [:]) == nil)
        #expect(TranscriptionEngine.dominantLanguage(weights: ["en": 0]) == nil)
    }

    @Test func mergesWeights() {
        #expect(TranscriptionEngine.merge(["tr": 10], ["tr": 5, "en": 3]) == ["tr": 15, "en": 3])
    }
}

@Suite struct SupportedLanguageTests {
    @Test func votesAmongSupportedLanguages() {
        var choice = LanguageChoice()
        #expect(choice.choose(votes: ["tr", "en", "tr"], supported: TranscriptionEngine.supportedLanguages) == "tr")
        #expect(TranscriptionEngine.supportedLanguages == ["en", "tr", "it"])
    }

    @Test func unsupportedDetectionsFallBack() {
        // A quick "А ну да" heard as Russian must not switch a Turkish conversation to Russian.
        var choice = LanguageChoice(current: "tr")
        #expect(choice.choose(votes: ["ru"], supported: TranscriptionEngine.supportedLanguages) == "tr")
    }

    @Test func samplesLongAudioAboutOnceAMinute() {
        let rate = 16_000
        #expect(TranscriptionEngine.languageSamples(count: rate * 20) == [0..<(rate * 20)])
        #expect(TranscriptionEngine.languageSamples(count: rate * 35).count == 3)
        let tenMinutes = TranscriptionEngine.languageSamples(count: rate * 600)
        #expect(tenMinutes.count == 10)
        #expect(tenMinutes.first?.lowerBound == 0)
        #expect(tenMinutes.last?.upperBound == rate * 600)
    }
}
