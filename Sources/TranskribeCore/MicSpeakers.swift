import Foundation

/// Who is speaking on the microphone. The mic isn't always one person: in a meeting room, or
/// with someone sitting next to you on a call, several voices reach it.
public enum MicSpeakers {
    /// A voice needs this much of the mic's speech, and this many seconds, to count as another
    /// person; anything less is a cough, a phantom split, or call audio leaking in.
    static let minimumShare = 0.15
    static let minimumSeconds: TimeInterval = 20
    /// A mic "voice" that mostly speaks while the call side is speaking is the call coming out of
    /// the speakers, not someone in the room.
    static let maximumCallOverlap = 0.5

    /// Mic + System: the person who talks most into the mic is the user ("Me"); other real
    /// voices in the room get their own numbers from `SpeakerID.firstInRoom`.
    /// `callSpeech` is when the call side was talking, on the mic's clock.
    public static func labelWithCall(_ segments: [RawSegment], turns: [SpeakerTurn],
                                     callSpeech: [(start: TimeInterval, end: TimeInterval)] = []) -> [RawSegment] {
        let assigned = SpeakerAssigner.assign(segments, turns: turns)
        let talk = talkTime(in: turns)
        guard let user = talk.max(by: { $0.value < $1.value })?.key else { return relabel(assigned) { _ in SpeakerID.me } }
        let total = talk.values.reduce(0, +)
        let others = firstAppearances(in: turns).filter { speaker in
            speaker != user && (talk[speaker] ?? 0) >= minimumSeconds && (talk[speaker] ?? 0) / total >= minimumShare
                && overlap(of: turns.filter { $0.speaker == speaker }, with: callSpeech) / (talk[speaker] ?? 1) <= maximumCallOverlap
        }
        var numbers: [Int: Int] = [:]
        for (index, speaker) in others.enumerated() { numbers[speaker] = SpeakerID.firstInRoom + index }
        return relabel(assigned) { speaker in speaker.flatMap { numbers[$0] } ?? SpeakerID.me }
    }

    /// Mic only (an in-person conversation): voices are kept apart like any recording; a single
    /// voice is the user talking to themselves (a voice note), so it's "Me".
    public static func labelAlone(_ segments: [RawSegment], turns: [SpeakerTurn]) -> [RawSegment] {
        let assigned = SpeakerAssigner.assign(segments, turns: turns)
        let voices = Set(assigned.compactMap(\.speaker))
        return voices.count > 1 ? assigned : relabel(assigned) { _ in SpeakerID.me }
    }

    // MARK: - Helpers

    private static func talkTime(in turns: [SpeakerTurn]) -> [Int: TimeInterval] {
        turns.reduce(into: [:]) { $0[$1.speaker, default: 0] += $1.end - $1.start }
    }

    private static func overlap(of turns: [SpeakerTurn], with spans: [(start: TimeInterval, end: TimeInterval)]) -> TimeInterval {
        turns.reduce(0) { total, turn in
            total + spans.reduce(0) { $0 + max(0, min(turn.end, $1.end) - max(turn.start, $1.start)) }
        }
    }

    private static func firstAppearances(in turns: [SpeakerTurn]) -> [Int] {
        var seen = Set<Int>()
        return turns.sorted { $0.start < $1.start }.map(\.speaker).filter { seen.insert($0).inserted }
    }

    private static func relabel(_ segments: [RawSegment], _ speaker: (Int?) -> Int) -> [RawSegment] {
        segments.map { var segment = $0; segment.speaker = speaker($0.speaker); return segment }
    }
}
