import AVFoundation

/// Recordings are saved at 64 kbps and imports are kept as they came, so transcription works from
/// the best audio there is. Once a conversation's text is final, its audio is re-encoded to what
/// speech needs: mono AAC at 16 kHz, exactly the band the speech models hear. That is a small
/// fraction of an imported WAV and about three quarters of a recording.
///
/// 48 kbps is the most AAC allows at 16 kHz, and the least that "Transcribe Again" doesn't notice:
/// on real Turkish calls it changed about as many words as inaudible noise does (Whisper flips on
/// any change), while 40 and 32 kbps dropped 3 to 4% of the words.
public enum AudioCompactor {
    public static let sampleRate: Double = 16_000
    public static let bitRate = 48_000
    /// Files already this close to the target are left alone: another lossy pass would cost
    /// quality for little space. A 64 kbps recording qualifies; a quieter call side often doesn't.
    static let worthwhileRatio = 1.25
    /// The re-encoded file must last as long as the original (AAC packets are 64 ms at 16 kHz).
    static let durationTolerance: TimeInterval = 0.25
    static let shortest: TimeInterval = 1

    public struct Result: Equatable, Sendable {
        /// The track's file name now (an imported .wav becomes .m4a).
        public let fileName: String
        /// The original, when the compact copy has a different name: delete it once the
        /// conversation points at `fileName`.
        public let original: URL?
        public let savedBytes: Int64
    }

    public enum CompactError: LocalizedError, Equatable {
        case durationChanged(TimeInterval, TimeInterval)

        public var errorDescription: String? {
            switch self {
            case let .durationChanged(before, after):
                "The compact copy lasted \(after) s instead of \(before) s."
            }
        }
    }

    /// Re-encodes `audio` when that saves real space. Returns nil when the file was left as it is.
    /// A copy with the same name replaces the original in one step; nothing is lost on failure.
    public static func compact(_ audio: URL) async throws -> Result? {
        let size = try fileSize(audio)
        let duration = try await AudioDecoder.duration(of: audio)
        guard duration >= shortest,
              Double(size) * 8 / duration > Double(bitRate) * worthwhileRatio else { return nil }

        let folder = audio.deletingLastPathComponent()
        let fileName = (audio.deletingPathExtension().lastPathComponent as NSString).appendingPathExtension("m4a")!
        let destination = folder.appendingPathComponent(fileName)
        let renames = fileName != audio.lastPathComponent
        if renames, FileManager.default.fileExists(atPath: destination.path) { return nil }

        let temporary = folder.appendingPathComponent("compact-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await encode(audio, to: temporary, bitRate: bitRate)

        let compactDuration = try await AudioDecoder.duration(of: temporary)
        guard abs(compactDuration - duration) <= durationTolerance else {
            throw CompactError.durationChanged(duration, compactDuration)
        }
        let saved = size - (try fileSize(temporary))
        guard saved > 0 else { return nil }

        guard renames else {
            _ = try FileManager.default.replaceItemAt(audio, withItemAt: temporary)
            return Result(fileName: fileName, original: nil, savedBytes: saved)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return Result(fileName: fileName, original: audio, savedBytes: saved)
    }

    // MARK: - Helpers

    /// Streams the first audio track through a 16 kHz mono decoder into the AAC encoder, so
    /// hours-long files never sit in memory.
    static func encode(_ source: URL, to destination: URL, bitRate: Int) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioDecoder.DecodeError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw AudioDecoder.DecodeError.readFailed(reader.error?.localizedDescription ?? "unknown error")
        }
        defer { reader.cancelReading() }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        // The file is finalized (its index written) when it goes out of scope.
        let file = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = try pcmBuffer(from: sampleBuffer, format: format) else { continue }
            try file.write(from: buffer)
        }
        if reader.status == .failed {
            throw AudioDecoder.DecodeError.readFailed(reader.error?.localizedDescription ?? "unknown error")
        }
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) throws -> AVAudioPCMBuffer? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        let status = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                                destination: buffer.floatChannelData![0])
        guard status == kCMBlockBufferNoErr else {
            throw AudioDecoder.DecodeError.readFailed("corrupt audio data (\(status))")
        }
        return buffer
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
