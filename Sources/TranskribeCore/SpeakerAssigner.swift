import Foundation

/// Attributes transcribed words to the speaker turns found by speaker detection, splitting
/// segments wherever the speaker changes mid-sentence.
public enum SpeakerAssigner {
    /// Words that fall in a gap between turns borrow the nearest turn within this distance.
    static let maxSnapDistance: TimeInterval = 1.0
    /// A speaker change inside one utterance needs at least this much evidence; shorter runs
    /// are timing jitter between the speech and speaker models.
    static let minimumRunWords = 3
    static let minimumRunDuration: TimeInterval = 0.8

    public static func assign(_ segments: [RawSegment], turns: [SpeakerTurn]) -> [RawSegment] {
        guard !turns.isEmpty else { return segments }
        return segments.flatMap { segment in
            segment.words.isEmpty
                ? [labeled(segment, speaker: speaker(from: segment.start, to: segment.end, in: turns))]
                : split(segment, turns: turns)
        }
    }

    /// The speaker who talks the most during `start...end`, or the nearest one if nobody does.
    static func speaker(from start: TimeInterval, to end: TimeInterval, in turns: [SpeakerTurn]) -> Int? {
        var overlap: [Int: TimeInterval] = [:]
        for turn in turns {
            let shared = min(end, turn.end) - max(start, turn.start)
            if shared > 0 { overlap[turn.speaker, default: 0] += shared }
        }
        if let best = overlap.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            return best.key
        }
        let nearest = turns.min { distance($0, start, end) < distance($1, start, end) }
        return nearest.flatMap { distance($0, start, end) <= maxSnapDistance ? $0.speaker : nil }
    }

    // MARK: - Helpers

    private static func split(_ segment: RawSegment, turns: [SpeakerTurn]) -> [RawSegment] {
        var speakers = segment.words.map { speaker(from: $0.start, to: $0.end, in: turns) }
        fillGaps(&speakers)
        smoothFlicker(&speakers, words: segment.words)

        var runs: [RawSegment] = []
        for (word, speaker) in zip(segment.words, speakers) {
            if let last = runs.last, last.speaker == speaker {
                runs[runs.count - 1].words.append(word)
                runs[runs.count - 1].end = word.end
            } else {
                runs.append(RawSegment(start: word.start, end: word.end, text: "", words: [word], speaker: speaker))
            }
        }
        return runs.map { run in
            var run = run
            run.text = run.words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            return run
        }
    }

    /// Words with no nearby turn inherit the previous speaker (or the next, at the start).
    private static func fillGaps(_ speakers: inout [Int?]) {
        var previous: Int?
        for index in speakers.indices {
            if let speaker = speakers[index] { previous = speaker } else { speakers[index] = previous }
        }
        let firstKnown = speakers.first { $0 != nil } ?? nil
        for index in speakers.indices where speakers[index] == nil {
            speakers[index] = firstKnown
        }
    }

    /// Repeatedly folds the weakest too-short run into its longer neighbor, so an utterance is
    /// only split where the evidence for a different speaker is substantial.
    private static func smoothFlicker(_ speakers: inout [Int?], words: [Word]) {
        var runs: [(range: Range<Int>, speaker: Int?)] = []
        for index in speakers.indices {
            if let last = runs.last, last.speaker == speakers[index] {
                runs[runs.count - 1].range = last.range.lowerBound..<(index + 1)
            } else {
                runs.append((index..<(index + 1), speakers[index]))
            }
        }
        func duration(_ range: Range<Int>) -> TimeInterval {
            words[range.upperBound - 1].end - words[range.lowerBound].start
        }
        func isWeak(_ range: Range<Int>) -> Bool {
            range.count < minimumRunWords || duration(range) < minimumRunDuration
        }
        while runs.count > 1,
              let weakest = runs.indices.filter({ isWeak(runs[$0].range) }).min(by: { duration(runs[$0].range) < duration(runs[$1].range) }) {
            let left = weakest > 0 ? weakest - 1 : nil
            let right = weakest < runs.count - 1 ? weakest + 1 : nil
            let target = [left, right].compactMap { $0 }.max { duration(runs[$0].range) < duration(runs[$1].range) }!
            let merged = min(runs[target].range.lowerBound, runs[weakest].range.lowerBound)..<max(runs[target].range.upperBound, runs[weakest].range.upperBound)
            runs[target].range = merged
            runs.remove(at: weakest)
            // Neighbors that now share a speaker become one run.
            var index = 0
            while index < runs.count - 1 {
                if runs[index].speaker == runs[index + 1].speaker {
                    runs[index].range = runs[index].range.lowerBound..<runs[index + 1].range.upperBound
                    runs.remove(at: index + 1)
                } else {
                    index += 1
                }
            }
        }
        for run in runs {
            for index in run.range { speakers[index] = run.speaker }
        }
    }

    private static func labeled(_ segment: RawSegment, speaker: Int?) -> RawSegment {
        var segment = segment
        segment.speaker = speaker
        return segment
    }

    private static func distance(_ turn: SpeakerTurn, _ start: TimeInterval, _ end: TimeInterval) -> TimeInterval {
        max(0, max(turn.start - end, start - turn.end))
    }
}
