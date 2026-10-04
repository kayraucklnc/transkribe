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
