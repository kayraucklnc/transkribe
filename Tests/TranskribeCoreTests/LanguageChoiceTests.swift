import Foundation
import Testing
@testable import TranskribeCore

@Suite struct LanguageChoiceTests {
    let supported: Set<String> = ["en", "it", "tr"]

    @Test func firstStretchTakesTheMajority() {
        var choice = LanguageChoice()
        #expect(choice.choose(votes: ["tr", "en", "tr"], supported: supported) == "tr")
    }

    @Test func oneShortWrongGuessDoesNotSwitch() {
        // A 20-second Turkish stretch guessed as English stays Turkish.
        var choice = LanguageChoice(current: "tr")
        #expect(choice.choose(votes: ["en"], supported: supported) == "tr")
        #expect(choice.choose(votes: ["tr"], supported: supported) == "tr")
        #expect(choice.candidate == nil)
    }

    @Test func twoStretchesInARowSwitch() {
        var choice = LanguageChoice(current: "tr")
        #expect(choice.choose(votes: ["en"], supported: supported) == "tr")
        #expect(choice.choose(votes: ["en"], supported: supported) == "en")
    }

    @Test func strongEvidenceSwitchesAtOnce() {
        var choice = LanguageChoice(current: "tr")
        #expect(choice.choose(votes: ["en", "en", "en", "tr"], supported: supported) == "en")
    }

    @Test func splitEvidenceKeepsTheLanguage() {
        var choice = LanguageChoice(current: "tr")
        #expect(choice.choose(votes: ["en", "en", "tr", "tr", "it"], supported: supported) == "tr")
    }

    @Test func otherLanguagesAreIgnored() {
        var choice = LanguageChoice(current: "tr")
        #expect(choice.choose(votes: ["is", "ru"], supported: supported) == "tr")
        var fresh = LanguageChoice()
        #expect(fresh.choose(votes: ["is"], supported: supported) == "en") // stable default
    }
}
