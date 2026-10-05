import AVFoundation

/// Records the default input device. With echo cancellation on, sound coming out of the
/// speakers is removed from the mic signal so a call isn't transcribed twice.
final class MicrophoneRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var writer: AudioFileWriter?

    func start(
        to url: URL,
        liveCopy: URL?,
        echoCancellation: Bool,
        onLevel: @escaping @Sendable (Float) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws {
        let input = engine.inputNode
        if echoCancellation {
            do {
                try input.setVoiceProcessingEnabled(true)
                input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                // Echo cancellation is a nice-to-have; record without it rather than fail.
            }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecordingError.noMicrophone
        }
        let writer = try AudioFileWriter(url: url, sampleRate: format.sampleRate, liveCopy: liveCopy)
        self.writer = writer

        let failure = FirstFailure(handler: onFailure)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            let host = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : ProcessInfo.processInfo.systemUptime
            do {
                onLevel(try writer.write(buffer, hostSeconds: host))
            } catch {
                failure.report(error)
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops recording and closes the file. Returns when the first sample was captured, or nil if nothing was.
    func stop() -> Double? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        defer { writer = nil }
        return writer?.finish()
    }
}
