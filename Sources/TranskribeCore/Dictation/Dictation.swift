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

/// Cleans up a dictation take before it reaches the model.
public enum DictationAudio {
    /// Drops the silence before you start and after you stop talking (keeping a quarter second
    /// either side), so the model doesn't invent words in the quiet.
    public static func trimmed(_ samples: [Float], sampleRate: Double = 16_000) -> [Float] {
        let frame = Int(sampleRate * 0.02)
        guard frame > 0, samples.count >= frame else { return [] }
        let loud: (Int) -> Bool = { start in
            var sum: Float = 0
            for index in start..<min(start + frame, samples.count) { sum += samples[index] * samples[index] }
            return sqrt(sum / Float(frame)) > 0.008
        }
        let starts = Swift.stride(from: 0, to: samples.count, by: frame)
        guard let first = starts.first(where: loud), let last = starts.reversed().first(where: loud) else { return [] }
        let margin = Int(sampleRate * 0.25)
        return Array(samples[max(0, first - margin)..<min(samples.count, last + frame + margin)])
    }
}

extension DictationAudio {
    /// 16-bit mono WAV.
    public static func writeWAV(_ samples: [Float], to url: URL, sampleRate: Int = 16_000) throws {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        try data.write(to: url, options: .atomic)
    }
}
