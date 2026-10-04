import Foundation
import Testing
@testable import TranskribeCore

@Suite struct DictationTextTests {
    @Test func joinsSegmentsIntoOneCleanString() {
        let segments = [
            RawSegment(start: 0, end: 2, text: "  Merhaba,  nasılsın? "),
            RawSegment(start: 2, end: 4, text: "Yarın görüşelim."),
        ]
        #expect(DictationText.finalize(segments, vocabulary: []) == "Merhaba, nasılsın? Yarın görüşelim.")
    }

    @Test func dropsHallucinationsAndLoops() {
        let segments = [
            RawSegment(start: 0, end: 2, text: "Send the report today."),
            RawSegment(start: 2, end: 4, text: "Thank you for watching!"),
        ]
        #expect(DictationText.finalize(segments, vocabulary: []) == "Send the report today.")
        #expect(DictationText.finalize([RawSegment(start: 0, end: 1, text: "Thank you.")], vocabulary: []) == "")
    }

    @Test func appliesVocabulary() {
        let segments = [RawSegment(start: 0, end: 2, text: "Talk to Kayrah about Transcribe")]
        #expect(DictationText.finalize(segments, vocabulary: ["Kayra", "Transkribe"]) == "Talk to Kayra about Transkribe")
    }

    @Test func emptyWhenNothingWasSaid() {
        #expect(DictationText.finalize([], vocabulary: []) == "")
        #expect(DictationText.finalize([RawSegment(start: 0, end: 1, text: " ... ")], vocabulary: []) == "")
    }
}

@Suite struct DictationSpeedTests {
    @Test func fastUsesTheBuiltInRecognizerOnlyWhenItKnowsEveryLanguage() {
        #expect(DictationSpeed.fast.quality(for: ["en", "it"]) == .instant)
        #expect(DictationSpeed.fast.quality(for: ["en", "tr"]) == .balanced)
        #expect(DictationSpeed.fast.quality(for: []) == .balanced)
    }

    @Test func balancedAndAccurateMapToWhisper() {
        #expect(DictationSpeed.balanced.quality(for: ["en"]) == .balanced)
        #expect(DictationSpeed.accurate.quality(for: ["tr"]) == .best)
    }
}

@Suite struct PasteTargetTests {
    @Test func textRolesAreEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            #expect(PasteTarget.isEditable(role: role, valueSettable: false, hasEditableAncestor: false))
        }
    }

    @Test func webContentEditableCounts() {
        #expect(PasteTarget.isEditable(role: "AXGroup", valueSettable: false, hasEditableAncestor: true))
        #expect(PasteTarget.isEditable(role: "AXWebArea", valueSettable: true, hasEditableAncestor: false))
    }

    @Test func buttonsAndListsAreNot() {
        #expect(!PasteTarget.isEditable(role: "AXButton", valueSettable: false, hasEditableAncestor: false))
        #expect(!PasteTarget.isEditable(role: nil, valueSettable: false, hasEditableAncestor: false))
    }
}

@Suite struct DictationLevelTests {
    @Test func mapsLoudnessToZeroOne() {
        #expect(DictationLevel.normalized(rms: 0) == 0)
        #expect(DictationLevel.normalized(rms: 1) == 1)
        let speech = DictationLevel.normalized(rms: 0.05)
        #expect(speech > 0.5 && speech < 1)
        #expect(DictationLevel.normalized(rms: 0.001) < 0.15)
    }

    @Test func waveformIsTallestInTheMiddleAndSymmetric() {
        let heights = DictationLevel.bars(count: 15, history: Array(repeating: 1, count: 20))
        #expect(heights.count == 15)
        #expect(heights[7] == heights.max())
        #expect(abs(heights[0] - heights[14]) < 0.0001)
        #expect(heights[0] < heights[7])
    }

    @Test func silenceIsFlatDots() {
        let heights = DictationLevel.bars(count: 15, history: Array(repeating: 0, count: 20))
        #expect(heights.allSatisfy { $0 == 0 })
    }
}

@Suite struct KeyComboTests {
    @Test func displaysModifiersInMacOrder() {
        let combo = KeyCombo(keyCode: 49, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.control | KeyCombo.option)
        #expect(combo.display == "⌃⌥⇧⌘ Space")
        #expect(KeyCombo(keyCode: 2, modifiers: KeyCombo.option, character: "d").display == "⌥D")
        #expect(KeyCombo(keyCode: 96, modifiers: 0).display == "F5")
    }

    @Test func needsAModifierUnlessItIsAFunctionKey() {
        #expect(!KeyCombo(keyCode: 2, modifiers: 0, character: "d").isValid)
        #expect(!KeyCombo(keyCode: 49, modifiers: 0).isValid)
        #expect(!KeyCombo(keyCode: 49, modifiers: KeyCombo.shift).isValid)
        #expect(KeyCombo(keyCode: 49, modifiers: KeyCombo.option).isValid)
        #expect(KeyCombo(keyCode: 111, modifiers: 0).isValid) // F12
    }

    @Test func roundTripsThroughJSON() throws {
        let combo = KeyCombo(keyCode: 2, modifiers: KeyCombo.control | KeyCombo.option, character: "d")
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
    }
}

@Suite struct DictationAudioTests {
    private func tone(_ seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(seconds * 16_000)).map { amplitude * sin(Float($0) * 0.2) }
    }

    @Test func trimsSilenceAroundSpeechKeepingAMargin() {
        let samples = tone(2, amplitude: 0) + tone(1, amplitude: 0.3) + tone(3, amplitude: 0.001)
        let trimmed = DictationAudio.trimmed(samples)
        #expect(abs(Double(trimmed.count) / 16_000 - 1.5) < 0.1)
    }

    @Test func keepsEverythingWhenItIsAllSpeech() {
        let samples = tone(1, amplitude: 0.3)
        #expect(DictationAudio.trimmed(samples).count == samples.count)
    }

    @Test func silenceTrimsToNothing() {
        #expect(DictationAudio.trimmed(tone(2, amplitude: 0.0005)).isEmpty)
    }
}
