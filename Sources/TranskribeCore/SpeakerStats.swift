import Foundation

/// How a conversation was shared between speakers.
public struct SpeakerShare: Equatable, Sendable, Identifiable {
    public var speaker: Int
    public var seconds: TimeInterval
    public var fraction: Double
    public var turns: Int

    public var id: Int { speaker }
}

public enum SpeakerStats {
    /// Talk time per speaker, most talkative first.
    public static func shares(of segments: [Segment]) -> [SpeakerShare] {
        var seconds: [Int: TimeInterval] = [:]
        var turns: [Int: Int] = [:]
        var previous: Int?
        for segment in segments {
            guard let speaker = segment.speaker else { continue }
            seconds[speaker, default: 0] += max(0, segment.end - segment.start)
            if speaker != previous { turns[speaker, default: 0] += 1 }
            previous = speaker
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [] }
        return seconds
            .map { SpeakerShare(speaker: $0.key, seconds: $0.value, fraction: $0.value / total, turns: turns[$0.key] ?? 0) }
            .sorted { $0.seconds > $1.seconds || ($0.seconds == $1.seconds && $0.speaker < $1.speaker) }
    }
}
