import AVFoundation

/// Keeps a short microphone take in memory at 16 kHz, ready to transcribe the moment it ends.
public final class DictationCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var isRunning = false

    public init() {}

    public func start(onLevel: @escaping @Sendable (Float) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecordingError.noMicrophone }
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false)!
        let resampler = try Resampler(from: mono)
        lock.withLock { samples = [] }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let downmixed = AudioFileWriter.downmix(buffer, to: mono) else { return }
            onLevel(AudioFileWriter.rms(downmixed))
            guard let converted = try? resampler.convert(downmixed) else { return }
            self.lock.withLock { self.samples.append(contentsOf: converted) }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// What has been heard so far, while still listening (for a live preview).
    public func snapshot(lastSeconds: Double) -> [Float] {
        lock.withLock {
            let count = Int(lastSeconds * PCMStore.sampleRate)
            return samples.count > count ? Array(samples.suffix(count)) : samples
        }
    }

    /// Stops listening and hands back everything heard.
    public func stop() -> [Float] {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        return lock.withLock {
            defer { samples = [] }
            return samples
        }
    }
}
