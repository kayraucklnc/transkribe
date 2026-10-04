import AVFoundation
import Testing
@testable import TranskribeCore

@Suite struct AudioDecoderTests {
    /// Writes a stereo 44.1 kHz sine wave so the decoder has to downmix and resample.
    private func makeSineFile(seconds: Double, ext: String = "wav") throws -> URL {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("sine.\(ext)")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                data[i] = 0.5 * sin(2 * .pi * 440 * Float(i) / 44_100)
            }
        }
        var settings = format.settings
        if ext == "m4a" {
            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2]
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        return url
    }

    @Test func decodesTo16kMono() async throws {
        let url = try makeSineFile(seconds: 2)
        let samples = try await AudioDecoder.decode(url: url)

        #expect(abs(samples.count - 32_000) < 400)
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.3 && peak < 0.8, "equal-power downmix keeps level without clipping; peak \(peak)")
    }

    @Test func decodesCompressedAudio() async throws {
        let url = try makeSineFile(seconds: 1, ext: "m4a")
        let samples = try await AudioDecoder.decode(url: url)
        #expect(abs(samples.count - 16_000) < 2_000)
    }

    @Test func reportsDuration() async throws {
        let url = try makeSineFile(seconds: 1.5)
        let duration = try await AudioDecoder.duration(of: url)
        #expect(abs(duration - 1.5) < 0.05)
    }

    @Test func decodesSilentEmptyFile() async throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("empty.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        _ = try AVAudioFile(forWriting: url, settings: format.settings)
        let samples = try? await AudioDecoder.decode(url: url)
        #expect(samples?.isEmpty ?? true)
    }

    @Test func rejectsFilesWithoutAudio() async throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: url)
        await #expect(throws: AudioDecoder.DecodeError.self) {
            _ = try await AudioDecoder.decode(url: url)
        }
    }

    @Test func extractsAudioToM4A() async throws {
        let source = try makeSineFile(seconds: 1)
        let destination = try Fixtures.temporaryDirectory().appendingPathComponent("audio.m4a")

        try await AudioDecoder.extractAudio(from: source, to: destination)

        let samples = try await AudioDecoder.decode(url: destination)
        #expect(abs(samples.count - 16_000) < 2_000)
    }
}
