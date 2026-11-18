import AVFoundation
import Testing
@testable import TranskribeCore

@Suite struct AudioFileWriterTests {
    private func buffer(seconds: Double, channels: AVAudioChannelCount = 2, value: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: channels)!
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = channel == 0 ? value : 0 }
        }
        return buffer
    }

    @Test func writesAndReportsFirstSampleTime() async throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("out.m4a")
        let writer = try AudioFileWriter(url: url, sampleRate: 48_000)

        try writer.write(buffer(seconds: 0.5), hostSeconds: 100)
        try writer.write(buffer(seconds: 0.5), hostSeconds: 100.5)

        #expect(writer.finish() == 100)
        #expect(abs(try await AudioDecoder.duration(of: url) - 1.0) < 0.1)
    }

    @Test func fillsCaptureGapsWithSilence() async throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("gap.m4a")
        let writer = try AudioFileWriter(url: url, sampleRate: 48_000)

        try writer.write(buffer(seconds: 0.5), hostSeconds: 10)
        try writer.write(buffer(seconds: 0.5), hostSeconds: 12) // 1.5 s gap

        _ = writer.finish()
        #expect(abs(try await AudioDecoder.duration(of: url) - 2.5) < 0.1)
    }

    @Test func finishWithoutAudioReturnsNilAndIgnoresLateWrites() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("none.m4a")
        let writer = try AudioFileWriter(url: url, sampleRate: 48_000)
        #expect(writer.finish() == nil)
        try writer.write(buffer(seconds: 0.1), hostSeconds: 1)
        #expect(writer.finish() == nil)
    }

    @Test func downmixAveragesChannelsAndReportsLevel() {
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let result = AudioFileWriter.downmix(buffer(seconds: 0.01, value: 0.8), to: mono)!
        #expect(result.floatChannelData![0][0] == 0.4)
        #expect(abs(AudioFileWriter.rms(result) - 0.4) < 0.001)
    }

    @Test func downmixRejectsMismatchedSampleRate() {
        let other = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        #expect(AudioFileWriter.downmix(buffer(seconds: 0.01), to: other) == nil)
    }

    /// Bluetooth headset mics in call mode run at 16 or 8 kHz, where AAC can't do 64 kbps,
    /// and pro interfaces at 96 kHz, where it can't encode at all.
    @Test(arguments: [8_000.0, 16_000, 24_000, 44_100, 48_000, 96_000])
    func recordsFromAnyMicSampleRate(rate: Double) async throws {
        let directory = try Fixtures.temporaryDirectory()
        let url = directory.appendingPathComponent("rate.m4a")
        let live = directory.appendingPathComponent("rate.pcm")
        let writer = try AudioFileWriter(url: url, sampleRate: rate, liveCopy: live)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let half = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate / 2))!
        half.frameLength = half.frameCapacity
        for i in 0..<Int(half.frameLength) { half.floatChannelData![0][i] = 0.5 * sin(Float(i) * 0.05) }

        try writer.write(half, hostSeconds: 5)
        try writer.write(half, hostSeconds: 5.5)
        _ = writer.finish()

        #expect(abs(try await AudioDecoder.duration(of: url) - 1) < 0.15)
        #expect(abs(PCMStore.Reader(url: live).duration - 1) < 0.05)
    }

    @Test func encodingKeepsTheBestBitRateTheEncoderAllows() throws {
        #expect(try AudioFileWriter.encoding(forInputRate: 48_000) == .init(sampleRate: 48_000, bitRate: 64_000))
        #expect(try AudioFileWriter.encoding(forInputRate: 16_000) == .init(sampleRate: 16_000, bitRate: 48_000))
        #expect(try AudioFileWriter.encoding(forInputRate: 8_000) == .init(sampleRate: 8_000, bitRate: 24_000))
        #expect(try AudioFileWriter.encoding(forInputRate: 96_000) == .init(sampleRate: 48_000, bitRate: 64_000))
    }

    @Test func firstFailureReportsOnce() {
        let count = LockedCounter()
        let failure = FirstFailure { _ in count.increment() }
        failure.report(RecordingError.noMicrophone)
        failure.report(RecordingError.noMicrophone)
        #expect(count.value == 1)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

@Suite struct LiveCopyTests {
    @Test func writerAlsoProducesA16kLiveCopy() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let live = directory.appendingPathComponent("live.pcm")
        let writer = try AudioFileWriter(url: directory.appendingPathComponent("out.m4a"), sampleRate: 48_000, liveCopy: live)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for i in 0..<48_000 { buffer.floatChannelData![0][i] = 0.5 * sin(Float(i) * 0.05) }

        try writer.write(buffer, hostSeconds: 10)
        try writer.write(buffer, hostSeconds: 12) // 1 s gap → silence in both files
        _ = writer.finish()

        let duration = PCMStore.Reader(url: live).duration
        #expect(abs(duration - 3) < 0.05)
    }
}
