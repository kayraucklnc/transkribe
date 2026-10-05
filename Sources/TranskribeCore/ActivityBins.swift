import Foundation

/// A conversation squeezed into a handful of bars for thumbnails: how much was said in each
/// slice of time, and by whom.
public enum ActivityBins {
    public struct Bin: Equatable, Sendable {
        /// Share of the slice that contains speech (0…1).
        public var level: Double
        /// Who spoke most in the slice.
        public var speaker: Int?
    }

    public static func make(segments: [Segment], duration: TimeInterval, count: Int) -> [Bin] {
        guard count > 0 else { return [] }
        guard duration > 0 else { return Array(repeating: Bin(level: 0, speaker: nil), count: count) }
        let width = duration / Double(count)
        var spoken = [TimeInterval](repeating: 0, count: count)
        var bySpeaker = [[Int: TimeInterval]](repeating: [:], count: count)
        for segment in segments {
            let first = max(0, min(count - 1, Int(segment.start / width)))
            let last = max(0, min(count - 1, Int(max(segment.start, segment.end - 0.0001) / width)))
            for index in first...last {
                let overlap = min(segment.end, Double(index + 1) * width) - max(segment.start, Double(index) * width)
                guard overlap > 0 else { continue }
                spoken[index] += overlap
                if let speaker = segment.speaker { bySpeaker[index][speaker, default: 0] += overlap }
            }
        }
        return (0..<count).map { index in
            Bin(
                level: min(1, spoken[index] / width),
                speaker: bySpeaker[index].max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
            )
        }
    }
}
