import AVFoundation

/// A recording that ends abruptly (force quit, crash, power loss) leaves an .m4a without its
/// index, which nothing can read. The live 16 kHz copy written alongside is plain samples and
/// survives, so the track is rebuilt from it.
public enum TrackRepair {
    /// Rebuilds `audio` from its live copy if `audio` can't be read. Returns true if it did.
    @discardableResult
    public static func repairIfNeeded(_ audio: URL) async throws -> Bool {
        if let duration = try? await AudioDecoder.duration(of: audio), duration > 0 { return false }
        let backup = audio.deletingLastPathComponent()
            .appendingPathComponent(RecordingSession.liveCopyName(for: audio.lastPathComponent))
        let reader = PCMStore.Reader(url: backup)
        guard reader.duration > 0 else { return false }

        let temporary = audio.deletingLastPathComponent().appendingPathComponent("repair-\(UUID().uuidString).m4a")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: PCMStore.sampleRate, channels: 1, interleaved: false)!
        do {
            let file = try AVAudioFile(forWriting: temporary, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: PCMStore.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            let piece: TimeInterval = 60
            for start in stride(from: 0, to: reader.duration, by: piece) {
                let samples = try reader.read(from: start, to: min(reader.duration, start + piece))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { continue }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
                try file.write(from: buffer)
            }
        } // closing the file writes the index
        _ = try FileManager.default.replaceItemAt(audio, withItemAt: temporary)
        return true
    }
}
