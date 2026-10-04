import AVFoundation

/// Forwards only the first error, so a failing disk doesn't flood the UI with alerts.
final class FirstFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var reported = false
    private let handler: @Sendable (Error) -> Void

    init(handler: @escaping @Sendable (Error) -> Void) {
        self.handler = handler
    }

    func report(_ error: Error) {
        let isFirst = lock.withLock {
            defer { reported = true }
            return !reported
        }
        if isFirst { handler(error) }
    }
}

/// Writes mono AAC (.m4a) from arbitrary PCM buffers, filling capture gaps with silence
/// so the file's timeline matches wall-clock time.
final class AudioFileWriter: @unchecked Sendable {
    static let bitRate = 64_000

    private let lock = NSLock()
    private var file: AVAudioFile?
    private let format: AVAudioFormat
    private var nextHostSeconds: Double?
    private var firstHostSeconds: Double?
    private var framesWritten: AVAudioFramePosition = 0

    init(url: URL, sampleRate: Double) throws {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Self.bitRate,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    /// Appends `buffer` captured at `hostSeconds` and returns its RMS level (0...1).
    @discardableResult
    func write(_ buffer: AVAudioPCMBuffer, hostSeconds: Double) throws -> Float {
        guard let mono = Self.downmix(buffer, to: format) else { return 0 }
        try lock.withLock {
            guard let file else { return }
            if firstHostSeconds == nil { firstHostSeconds = hostSeconds }
            if let expected = nextHostSeconds {
                let gap = hostSeconds - expected
                if gap > 0.05 { try writeSilence(seconds: gap, to: file) }
            }
            try file.write(from: mono)
            framesWritten += AVAudioFramePosition(mono.frameLength)
            nextHostSeconds = hostSeconds + Double(mono.frameLength) / format.sampleRate
        }
        return Self.rms(mono)
    }

    /// Closes the file (finalizing the AAC container). Returns when the first sample
    /// was captured, or nil if nothing was written. Later writes are ignored.
    func finish() -> Double? {
        lock.withLock {
            file = nil
            return framesWritten > 0 ? firstHostSeconds : nil
        }
    }

    // MARK: - Helpers

    private func writeSilence(seconds: Double, to file: AVAudioFile) throws {
        var remaining = AVAudioFrameCount(seconds * format.sampleRate)
        let chunk: AVAudioFrameCount = 4096
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
        while remaining > 0 {
            let count = min(chunk, remaining)
            silence.frameLength = count
            memset(silence.floatChannelData![0], 0, Int(count) * MemoryLayout<Float>.size)
            try file.write(from: silence)
            framesWritten += AVAudioFramePosition(count)
            remaining -= count
        }
    }

    /// Averages all channels into one. Input must already be at the writer's sample rate.
    static func downmix(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format.sampleRate == format.sampleRate,
              let source = buffer.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else { return nil }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let stride = buffer.format.isInterleaved ? channels : 1
        let destination = mono.floatChannelData![0]
        mono.frameLength = buffer.frameLength
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += buffer.format.isInterleaved
                    ? source[0][frame * stride + channel]
                    : source[channel][frame]
            }
            destination[frame] = sum / Float(channels)
        }
        return mono
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(buffer.frameLength)))
    }
}
