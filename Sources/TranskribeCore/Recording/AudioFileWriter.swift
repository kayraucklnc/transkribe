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
    /// The bitrate recordings aim for; low-rate inputs get the most the encoder allows below it.
    static let bitRate = 64_000
    /// AAC can't encode above 48 kHz, so faster inputs (pro interfaces at 96 kHz) are resampled.
    static let maxSampleRate: Double = 48_000

    struct Encoding: Equatable {
        let sampleRate: Double
        let bitRate: Int
    }

    private let lock = NSLock()
    private var file: AVAudioFile?
    /// Mono at the input's rate: what `downmix` produces and what levels and timing are measured on.
    private let inputFormat: AVAudioFormat
    /// Mono at the file's rate, when that differs from the input's.
    private let encoderResampler: Resampler?
    private var nextHostSeconds: Double?
    private var firstHostSeconds: Double?
    private var framesWritten: AVAudioFramePosition = 0
    /// Optional readable 16 kHz copy, so transcription can run while recording.
    private let liveWriter: PCMStore.Writer?
    private let liveResampler: Resampler?

    init(url: URL, sampleRate: Double, liveCopy: URL? = nil) throws {
        inputFormat = Self.monoFormat(sampleRate)
        let encoding = try Self.encoding(forInputRate: sampleRate)
        let fileFormat = Self.monoFormat(encoding.sampleRate)
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: encoding.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: encoding.bitRate,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        encoderResampler = encoding.sampleRate == sampleRate ? nil : try Resampler(from: inputFormat, to: encoding.sampleRate)
        if let liveCopy {
            liveWriter = try PCMStore.Writer(url: liveCopy)
            liveResampler = try Resampler(from: fileFormat)
        } else {
            liveWriter = nil
            liveResampler = nil
        }
    }

    /// The file format for an input at `rate`: its own rate up to 48 kHz, and the best bitrate up to
    /// 64 kbps that the AAC encoder takes there. A Bluetooth headset in call mode runs at 16 kHz,
    /// where 64 kbps is refused ('!dat', error 560226676) and 48 kbps is the most there is.
    static func encoding(forInputRate rate: Double) throws -> Encoding {
        let fileRate = min(rate, maxSampleRate)
        var aac = AudioStreamBasicDescription(
            mSampleRate: fileRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0
        )
        guard rate > 0,
              let target = AVAudioFormat(streamDescription: &aac),
              let converter = AVAudioConverter(from: monoFormat(fileRate), to: target),
              let best = converter.applicableEncodeBitRates?.map(\.intValue).filter({ $0 <= bitRate }).max()
        else { throw RecordingError.unsupportedSampleRate(rate) }
        return Encoding(sampleRate: fileRate, bitRate: best)
    }

    /// Appends `buffer` captured at `hostSeconds` and returns its RMS level (0...1).
    @discardableResult
    func write(_ buffer: AVAudioPCMBuffer, hostSeconds: Double) throws -> Float {
        guard let mono = Self.downmix(buffer, to: inputFormat) else { return 0 }
        try lock.withLock {
            guard let file, let encodable = try encodable(mono) else { return }
            if firstHostSeconds == nil { firstHostSeconds = hostSeconds }
            if let expected = nextHostSeconds {
                let gap = hostSeconds - expected
                if gap > 0.05 { try writeSilence(seconds: gap, to: file) }
            }
            try file.write(from: encodable)
            try writeLiveCopy(encodable)
            framesWritten += AVAudioFramePosition(mono.frameLength)
            nextHostSeconds = hostSeconds + Double(mono.frameLength) / inputFormat.sampleRate
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
        var remaining = AVAudioFrameCount(seconds * file.processingFormat.sampleRate)
        let chunk: AVAudioFrameCount = 4096
        guard let silence = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return }
        while remaining > 0 {
            let count = min(chunk, remaining)
            silence.frameLength = count
            memset(silence.floatChannelData![0], 0, Int(count) * MemoryLayout<Float>.size)
            try file.write(from: silence)
            try writeLiveCopy(silence)
            framesWritten += AVAudioFramePosition(count)
            remaining -= count
        }
    }

    /// `mono` at the file's rate (the same buffer when the input already is).
    private func encodable(_ mono: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        guard let encoderResampler else { return mono }
        return try encoderResampler.convertBuffer(mono)
    }

    private func writeLiveCopy(_ buffer: AVAudioPCMBuffer) throws {
        guard let liveWriter, let liveResampler else { return }
        try liveWriter.append(try liveResampler.convert(buffer))
    }

    private static func monoFormat(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
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

/// Streams mono audio from any rate to another (16 kHz by default), keeping converter state between buffers.
final class Resampler {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat

    init(from input: AVAudioFormat, to rate: Double = PCMStore.sampleRate) throws {
        output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw AudioDecoder.DecodeError.readFailed("unsupported recording format")
        }
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let out = try convertBuffer(buffer) else { return [] }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }

    func convertBuffer(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        // A same-rate converter still buffers internally and drops samples when streamed.
        if buffer.format == output { return buffer }
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return out
    }
}
