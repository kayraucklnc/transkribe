import Foundation

/// Speech recognizers occasionally skip a whole sentence. Comparing where the audio has speech
/// with where text came out finds those holes so they can be transcribed on their own.
public enum GapFinder {
    /// Holes shorter than this are pauses inside speech, not lost sentences.
    static let minimumGap: TimeInterval = 1.2
    static let frame = 320 // 20 ms at 16 kHz

    public static func uncovered(speech: [Range<TimeInterval>], segments: [RawSegment]) -> [Range<TimeInterval>] {
        let covered = segments.map { ($0.start - 0.15)..<($0.end + 0.15) }.sorted { $0.lowerBound < $1.lowerBound }
        var gaps: [Range<TimeInterval>] = []
        for region in speech {
            var cursor = region.lowerBound
            for range in covered where range.upperBound > cursor && range.lowerBound < region.upperBound {
                if range.lowerBound > cursor { gaps.append(cursor..<range.lowerBound) }
                cursor = max(cursor, range.upperBound)
            }
            if cursor < region.upperBound { gaps.append(cursor..<region.upperBound) }
        }
        return gaps.filter { $0.upperBound - $0.lowerBound >= minimumGap }
    }

    /// Stretches of speech, from loudness relative to the recording's own noise floor.
    public static func speechRegions(in samples: [Float], sampleRate: Double = 16_000) -> [Range<TimeInterval>] {
        let energies = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start -> Float in
            var sum: Float = 0
            for index in start..<(start + frame) { sum += samples[index] * samples[index] }
            return (sum / Float(frame)).squareRoot()
        }
        guard !energies.isEmpty else { return [] }
        let sorted = energies.sorted()
        let floor = sorted[sorted.count / 10]
        let threshold = max(floor * 4, 0.01)
        var regions: [Range<TimeInterval>] = []
        var start: Int?
        var silence = 0
        for (index, energy) in energies.enumerated() {
            if energy >= threshold {
                if start == nil { start = index }
                silence = 0
            } else if let open = start {
                silence += 1
                if silence > 15 { // 300 ms of quiet closes a region
                    regions.append(time(open, sampleRate)..<time(index - silence + 1, sampleRate))
                    start = nil
                    silence = 0
                }
            }
        }
        if let open = start { regions.append(time(open, sampleRate)..<time(energies.count - silence, sampleRate)) }
        return regions.filter { $0.upperBound - $0.lowerBound >= 0.3 }
    }

    private static func time(_ frameIndex: Int, _ rate: Double) -> TimeInterval {
        Double(frameIndex * frame) / rate
    }
}
