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
