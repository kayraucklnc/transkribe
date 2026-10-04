import Foundation

/// Without headphones the microphone also hears the call coming out of the speakers. That
/// "bleed" is a delayed, quieter copy of the system audio, so its loudness contour follows the
/// system channel's contour closely; your own voice doesn't.
public enum EchoDetector {
    static let frame = 320            // 20 ms at 16 kHz
    static let maxLagFrames = 15      // speakers-to-mic delay up to 300 ms
    static let threshold: Float = 0.75

    public static func isBleed(mic: [Float], system: [Float]) -> Bool {
        let micEnvelope = envelope(mic), systemEnvelope = envelope(system)
        let count = min(micEnvelope.count, systemEnvelope.count)
        guard count > maxLagFrames * 2, (systemEnvelope.max() ?? 0) > 0.01 else { return false }
        var best: Float = 0
        for lag in 0...maxLagFrames {
            best = max(best, correlation(Array(micEnvelope[lag..<count]), Array(systemEnvelope[0..<(count - lag)])))
        }
        return best >= threshold
    }

    static func envelope(_ samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            var sum: Float = 0
            for index in start..<(start + frame) { sum += samples[index] * samples[index] }
            return (sum / Float(frame)).squareRoot()
        }
    }

    static func correlation(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count > 1 else { return 0 }
        let meanA = a.reduce(0, +) / Float(a.count), meanB = b.reduce(0, +) / Float(b.count)
        var numerator: Float = 0, varianceA: Float = 0, varianceB: Float = 0
        for index in a.indices {
            let x = a[index] - meanA, y = b[index] - meanB
            numerator += x * y
            varianceA += x * x
            varianceB += y * y
        }
        let denominator = (varianceA * varianceB).squareRoot()
        return denominator > 0 ? numerator / denominator : 0
    }
}
