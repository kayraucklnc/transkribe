import AVFoundation

/// Turns any audio or video file AVFoundation understands into what the speech model needs.
public enum AudioDecoder {
    public static let sampleRate: Double = 16_000

    public enum DecodeError: LocalizedError, Equatable {
        case noAudioTrack
        case readFailed(String)
        case exportFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noAudioTrack: "This file doesn't contain any audio."
            case .readFailed(let reason): "Couldn't read the audio: \(reason)"
            case .exportFailed(let reason): "Couldn't import the audio: \(reason)"
            }
        }
    }

    /// Decodes the first audio track into 16 kHz mono Float32 samples.
    public static func decode(url: URL) async throws -> [Float] {
        try await decode(url: url, range: nil)
    }

    /// Decodes only `start..<end` seconds, so hours-long files can be processed in slices.
    public static func decode(url: URL, from start: TimeInterval, to end: TimeInterval) async throws -> [Float] {
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 48_000),
            end: CMTime(seconds: end, preferredTimescale: 48_000)
        )
        return try await decode(url: url, range: range)
    }

    private static func decode(url: URL, range: CMTimeRange?) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let track = try await firstAudioTrack(of: asset)
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw DecodeError.readFailed(error.localizedDescription)
        }
        if let range { reader.timeRange = range }
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
            throw DecodeError.readFailed(reader.error?.localizedDescription ?? "unknown error")
        }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try append(buffer, to: &samples)
        }
        if reader.status == .failed {
            throw DecodeError.readFailed(reader.error?.localizedDescription ?? "unknown error")
        }
        return samples
    }

    public static func duration(of url: URL) async throws -> TimeInterval {
        let duration = try await AVURLAsset(url: url).load(.duration)
        return duration.isNumeric ? duration.seconds : 0
    }

    /// Writes the audio of `source` (audio or video) to `destination` as AAC in an .m4a container.
    public static func extractAudio(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        _ = try await firstAudioTrack(of: asset)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw DecodeError.exportFailed("unsupported format")
        }
        try? FileManager.default.removeItem(at: destination)
        if #available(macOS 15, *) {
            do {
                try await session.export(to: destination, as: .m4a)
            } catch {
                throw DecodeError.exportFailed(error.localizedDescription)
            }
        } else {
            session.outputURL = destination
            session.outputFileType = .m4a
            await session.export()
            if session.status != .completed {
                throw DecodeError.exportFailed(session.error?.localizedDescription ?? "unknown error")
            }
        }
    }

    // MARK: - Helpers

    private static func firstAudioTrack(of asset: AVURLAsset) async throws -> AVAssetTrack {
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw DecodeError.noAudioTrack
        }
        guard let track = tracks.first else { throw DecodeError.noAudioTrack }
        return track
    }

    private static func append(_ sampleBuffer: CMSampleBuffer, to samples: inout [Float]) throws {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(block)
        let count = length / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let start = samples.count
        samples.append(contentsOf: repeatElement(0, count: count))
        let status = samples.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                       destination: raw.baseAddress!.advanced(by: start * MemoryLayout<Float>.size))
        }
        guard status == kCMBlockBufferNoErr else {
            throw DecodeError.readFailed("corrupt audio data (\(status))")
        }
    }
}
