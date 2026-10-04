import Foundation

/// How dictation trades speed for accuracy, in words people understand.
public enum DictationSpeed: String, Codable, CaseIterable, Sendable, Identifiable {
    case fast
    case balanced
    case accurate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .accurate: "Accurate"
        }
    }

    public var detail: String {
        switch self {
        case .fast: "Text appears almost instantly. Uses the Mac's built-in recognizer when it knows your languages."
        case .balanced: "A moment longer, very accurate in every language."
        case .accurate: "Takes a little longer. Best for names, numbers and mixed languages."
        }
    }

    /// The transcription setup behind each choice. macOS can't transcribe some languages
    /// (e.g. Turkish), so "Fast" falls back to the balanced model for them.
    public func quality(for languages: [String]) -> TranscriptionQuality {
        switch self {
        case .fast: EngineCatalog.recommendedQuality(for: languages)
        case .balanced: .balanced
        case .accurate: .best
        }
    }
}

/// Turns what the model heard into the text that gets pasted.
public enum DictationText {
    public static func finalize(_ segments: [RawSegment], vocabulary: [String]) -> String {
        let pieces = segments
            .map { RepetitionFilter.collapse($0.text).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !Hallucinations.isHallucination($0) }
        let joined = pieces.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard joined.contains(where: \.isLetter) || joined.contains(where: \.isNumber) else { return "" }
        return vocabulary.isEmpty ? joined : VocabularyCorrector.correct(joined, vocabulary: vocabulary)
    }
}

/// Whether the focused accessibility element accepts typed text.
public enum PasteTarget {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    public static func isEditable(role: String?, valueSettable: Bool, hasEditableAncestor: Bool) -> Bool {
        guard let role else { return false }
        return textRoles.contains(role) || hasEditableAncestor || (valueSettable && role != "AXButton" && role != "AXCheckBox"
            && role != "AXSlider" && role != "AXPopUpButton")
    }
}

/// Microphone loudness for the on-screen waveform.
public enum DictationLevel {
    /// RMS amplitude → 0...1 on a decibel scale (-50 dB is silence, -10 dB is loud speech).
    public static func normalized(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(1, max(0, (decibels + 50) / 40))
    }

    /// Bar heights (0...1) for a symmetric waveform: newest level in the middle, older levels
    /// ripple outwards, tapering towards the edges.
    public static func bars(count: Int, history: [Double]) -> [Double] {
        guard count > 0 else { return [] }
        let center = Double(count - 1) / 2
        return (0..<count).map { index in
            let distance = abs(Double(index) - center)
            let age = Int(distance.rounded())
            let level = age < history.count ? history[history.count - 1 - age] : 0
            let taper = exp(-pow(distance / (Double(count) * 0.3), 2))
            return level * taper
        }
    }
}
