import AVFoundation
import Testing
@testable import TranskribeCore

@Suite struct AudioCompactorTests {
    /// Speech-like audio (a few tones and noise, changing every 200 ms) with one loud click at
    /// `click` seconds, so timing can be checked after re-encoding.
    private func signal(seconds: Double, sampleRate: Double, click: Double) -> [Float] {
        var generator = SystemRandomNumberGenerator()
        let clickAt = Int(click * sampleRate)
        return (0..<Int(seconds * sampleRate)).map { index in
            if (clickAt..<clickAt + 32).contains(index) { return 0.95 }
            let time = Double(index) / sampleRate
            let pitch = 140 + 60 * sin(time * 2)
            let voice = 0.12 * sin(2 * .pi * pitch * time) + 0.06 * sin(2 * .pi * pitch * 3 * time)
            return Float(voice) + Float.random(in: -0.02...0.02, using: &generator)
        }
    }

    private func write(_ samples: [Float], sampleRate: Double, to url: URL, settings: [String: Any]) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    /// What the app records: AAC at 64 kbps at the device's rate.
    private func recording(seconds: Double, click: Double = 2, in directory: URL, name: String = "microphone.m4a") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try write(signal(seconds: seconds, sampleRate: 48_000, click: click), sampleRate: 48_000, to: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: AudioFileWriter.bitRate,
        ])
        return url
    }

    private func size(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func loudestSample(in url: URL) async throws -> TimeInterval {
        let samples = try await AudioDecoder.decode(url: url)
        let index = samples.indices.max { abs(samples[$0]) < abs(samples[$1]) }!
        return Double(index) / AudioDecoder.sampleRate
    }

    @Test func shrinksARecordingInPlace() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let audio = try recording(seconds: 20, in: directory)
        let before = try size(audio)

        let result = try #require(try await AudioCompactor.compact(audio))

        #expect(result.fileName == "microphone.m4a")
        #expect(result.original == nil)
        #expect(try size(audio) < before * 85 / 100)
        #expect(result.savedBytes == before - (try size(audio)))
        #expect(abs(try await AudioDecoder.duration(of: audio) - 20) < 0.1)
        // Only the compact file is left in the folder.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["microphone.m4a"])
    }

    @Test func keepsEverythingWhereItWas() async throws {
        // Lines are tied to times in the audio: re-encoding must not shift them.
        let directory = try Fixtures.temporaryDirectory()
        let audio = try recording(seconds: 12, click: 7.25, in: directory)
        let before = try await loudestSample(in: audio)

        _ = try #require(try await AudioCompactor.compact(audio))

        #expect(abs(try await loudestSample(in: audio) - before) < 0.005)
    }

    @Test func leavesCompactAudioAlone() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let audio = try recording(seconds: 10, in: directory)
        _ = try #require(try await AudioCompactor.compact(audio))
        let compacted = try size(audio)

        #expect(try await AudioCompactor.compact(audio) == nil)
        #expect(try size(audio) == compacted)
    }

    @Test func turnsAnImportedWAVIntoM4AAndKeepsTheOriginalForTheCaller() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let wav = directory.appendingPathComponent("audio.wav")
        try write(signal(seconds: 8, sampleRate: 44_100, click: 3), sampleRate: 44_100, to: wav, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])

        let result = try #require(try await AudioCompactor.compact(wav))

        #expect(result.fileName == "audio.m4a")
        #expect(result.original == wav)
        #expect(FileManager.default.fileExists(atPath: wav.path)) // deleted once the conversation points at the new file
        let compact = directory.appendingPathComponent("audio.m4a")
        #expect(try size(compact) * 8 < (try size(wav)))
        #expect(abs(try await AudioDecoder.duration(of: compact) - 8) < 0.1)
    }

    @Test func neverOverwritesAnotherFile() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let wav = directory.appendingPathComponent("audio.wav")
        try write(signal(seconds: 4, sampleRate: 44_100, click: 1), sampleRate: 44_100, to: wav, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        let existing = directory.appendingPathComponent("audio.m4a")
        try Data("someone else's".utf8).write(to: existing)

        #expect(try await AudioCompactor.compact(wav) == nil)
        #expect(try Data(contentsOf: existing) == Data("someone else's".utf8))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == ["audio.wav", "audio.m4a"])
    }

    @Test func skipsAudioTooShortToMatter() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let audio = try recording(seconds: 0.5, click: 0.1, in: directory)
        #expect(try await AudioCompactor.compact(audio) == nil)
    }
}
