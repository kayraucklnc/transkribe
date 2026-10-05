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
        #expect(TranscriptionEngine.vote(["tr", "en", "tr"], fallback: nil) == "tr")
        #expect(TranscriptionEngine.supportedLanguages == ["en", "tr", "it"])
    }

    @Test func unsupportedDetectionsFallBack() {
        // A quick "А ну да" heard as Russian must not switch a Turkish conversation to Russian.
        #expect(TranscriptionEngine.vote(["ru"], fallback: "tr") == "tr")
        #expect(TranscriptionEngine.vote(["ru", "en"], fallback: "tr") == "en")
        #expect(TranscriptionEngine.vote([], fallback: nil) == "en")
    }
}
