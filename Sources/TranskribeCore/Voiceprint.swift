import Foundation

/// A voice as numbers (a speaker embedding): recordings of the same person land close together.
public enum Voiceprint {
    public static func normalized(_ values: [Float]) -> [Float] {
        let length = sqrt(values.reduce(0) { $0 + $1 * $1 })
        return length > 0 ? values.map { $0 / length } : values
    }

    /// Cosine similarity of two normalized voiceprints: 1 is the same voice.
    public static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// Folds a new sample of someone's voice into what was learned from `weight` earlier ones.
    public static func merge(_ existing: [Float]?, weight: Int, with sample: [Float]) -> [Float] {
        guard let existing, existing.count == sample.count, weight > 0 else { return normalized(sample) }
        let w = Float(weight)
        return normalized(zip(existing, sample).map { ($0 * w + $1) / (w + 1) })
    }
}

/// Recognizes known people among a recording's voices.
public enum VoiceMatcher {
    /// Same-voice similarity for this embedding model typically sits well above this.
    static let threshold: Float = 0.62
    /// The best person must beat the runner-up by this much, or it's a guess.
    static let margin: Float = 0.06

    /// Speaker → person, one-to-one, only for confident matches.
    public static func match(voices: [Int: [Float]], people: [(id: UUID, voiceprint: [Float])]) -> [Int: UUID] {
        var candidates: [(speaker: Int, person: UUID, score: Float)] = []
        for (speaker, voice) in voices {
            let scores = people.map { (person: $0.id, score: Voiceprint.similarity(voice, $0.voiceprint)) }
                .sorted { $0.score > $1.score }
            guard let best = scores.first, best.score >= threshold,
                  scores.count < 2 || best.score - scores[1].score >= margin else { continue }
            candidates.append((speaker, best.person, best.score))
        }
        // Strongest matches first; a person is claimed by one voice only.
        var result: [Int: UUID] = [:]
        var claimed = Set<UUID>()
        for candidate in candidates.sorted(by: { $0.score > $1.score }) where !claimed.contains(candidate.person) {
            result[candidate.speaker] = candidate.person
            claimed.insert(candidate.person)
        }
        return result
    }
}

/// Where to listen to one speaker on their own, to learn their voice.
public enum VoiceClips {
    static let minimumLength: TimeInterval = 2
    static let maximumLength: TimeInterval = 10
    static let count = 4

    /// The longest stretches where only `speaker` talks, trimmed to 10 s, longest first.
    public static func ranges(for speaker: Int, in segments: [Segment]) -> [(start: TimeInterval, end: TimeInterval)] {
        let others = segments.filter { $0.speaker != speaker && $0.speaker != nil }
        var ranges: [(start: TimeInterval, end: TimeInterval)] = []
        for segment in segments where segment.speaker == speaker {
            var pieces = [(start: segment.start, end: segment.end)]
            for other in others where other.start < segment.end && segment.start < other.end {
                pieces = pieces.flatMap { piece -> [(start: TimeInterval, end: TimeInterval)] in
                    guard other.start < piece.end, piece.start < other.end else { return [piece] }
                    return [(piece.start, other.start), (other.end, piece.end)].filter { $0.1 > $0.0 }
                }
            }
            ranges += pieces.filter { $0.end - $0.start >= minimumLength }
                .map { (start: $0.start, end: min($0.end, $0.start + maximumLength)) }
        }
        return Array(ranges.sorted { ($0.end - $0.start) > ($1.end - $1.start) }.prefix(count))
    }
}
