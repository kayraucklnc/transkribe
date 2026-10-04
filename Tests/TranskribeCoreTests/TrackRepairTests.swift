import AVFoundation
import Testing
@testable import TranskribeCore

@Suite struct TrackRepairTests {
    private func makeLiveCopy(seconds: Double, in directory: URL, name: String) throws -> URL {
        let url = directory.appendingPathComponent(RecordingSession.liveCopyName(for: name))
        let samples = (0..<Int(seconds * 16_000)).map { 0.4 * sin(Float($0) * 0.05) }
        try PCMStore.Writer(url: url).append(samples)
        return url
    }

    @Test func rebuildsUnreadableRecordingFromLiveCopy() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let audio = directory.appendingPathComponent("microphone.m4a")
        try Data("not a finished m4a".utf8).write(to: audio) // what a force-quit leaves behind
        _ = try makeLiveCopy(seconds: 3, in: directory, name: "microphone.m4a")

        let repaired = try await TrackRepair.repairIfNeeded(audio)

        #expect(repaired)
        #expect(abs(try await AudioDecoder.duration(of: audio) - 3) < 0.2)
    }

    @Test func leavesReadableAudioAlone() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let audio = directory.appendingPathComponent("system.m4a")
        let writer = try AudioFileWriter(url: audio, sampleRate: 48_000)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        try writer.write(buffer, hostSeconds: 0)
        _ = writer.finish()
        _ = try makeLiveCopy(seconds: 5, in: directory, name: "system.m4a")

        #expect(try await TrackRepair.repairIfNeeded(audio) == false)
    }

    @Test func unreadableWithoutBackupStaysAnError() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let audio = directory.appendingPathComponent("microphone.m4a")
        try Data("broken".utf8).write(to: audio)
        #expect(try await TrackRepair.repairIfNeeded(audio) == false)
    }
}
