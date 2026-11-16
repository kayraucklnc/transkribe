import Foundation

/// Short, soft tones that say "recording started" (rising) and "recording stopped" (falling),
/// made in code so there are no audio files to ship.
public enum Chime: CaseIterable, Sendable {
    case start
    case stop
    case reminder

    /// Note frequencies in hertz, played one after another.
    public var notes: [Double] {
        switch self {
        case .start: [659.26, 987.77] // E5 → B5
        case .stop: [987.77, 659.26] // B5 → E5
        case .reminder: [880.0, 880.0] // A5, twice
        }
    }

    static let noteDuration = 0.16
    static let gap = 0.035
    static let amplitude = 0.22

    /// 16-bit mono PCM samples, in -1…1.
    public func samples(sampleRate: Int = 44_100) -> [Float] {
        let noteLength = Int(Self.noteDuration * Double(sampleRate))
        let gapLength = Int(Self.gap * Double(sampleRate))
        // The last note rings longer so the chime ends softly.
        let tail = noteLength
        var output: [Float] = []
        for (index, frequency) in notes.enumerated() {
            let isLast = index == notes.count - 1
            let length = noteLength + (isLast ? tail : 0)
            for n in 0..<length {
                let t = Double(n) / Double(sampleRate)
                let attack = min(1, t / 0.008)
                let decay = exp(-t * (isLast ? 9 : 14))
                // A touch of the octave makes it sound like a bell rather than a beep.
                let tone = sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t)
                output.append(Float(Self.amplitude * attack * decay * tone / 1.25))
            }
            if !isLast { output.append(contentsOf: repeatElement(0, count: gapLength)) }
        }
        return output
    }

    /// The chime as a WAV file in memory, ready for `NSSound(data:)` or `AVAudioPlayer(data:)`.
    public func wav(sampleRate: Int = 44_100) -> Data {
        let pcm = samples(sampleRate: sampleRate).map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        let dataSize = UInt32(pcm.count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        pcm.forEach { append($0) }
        return data
    }
}
