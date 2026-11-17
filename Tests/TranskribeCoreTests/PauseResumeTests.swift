import Foundation
import Testing
@testable import TranskribeCore

/// "Continue Anyway" looked broken: a paused transcription only looked again after 10 seconds,
/// and nothing said it had resumed until the next text came out.
@Suite struct PauseResumeTests {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = true
        var paused: Bool { lock.withLock { value } }
        func resume() { lock.withLock { value = false } }
    }

    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var reasons: [String?] = []
        func add(_ reason: String?) { lock.withLock { reasons.append(reason) } }
        var all: [String?] { lock.withLock { reasons } }
    }

    private final class OneLine: SpeechEngine, @unchecked Sendable {
        func prepare(onProgress: @escaping @Sendable (TranscriptionEngine.Preparation) -> Void) async throws {}
        func transcribe(samples: [Float], onSegments: @escaping @Sendable ([RawSegment]) -> Void) async throws -> TranscriptionEngine.Output {
            TranscriptionEngine.Output(segments: [RawSegment(start: 0, end: 1, text: " Devam.")], language: "tr")
        }
    }

    private struct Silence: AudioSource {
        var isComplete: Bool { true }
        func availableDuration() async throws -> TimeInterval { 2 }
        func read(from start: TimeInterval, to end: TimeInterval) async throws -> [Float] {
            Array(repeating: 0, count: Int((end - start) * 16_000))
        }
    }

    @Test func resumesWithinASecondAndSaysSo() async throws {
        let flag = Flag(), reports = Reports()
        let transcriber = TrackTranscriber(source: Silence(), engine: OneLine(), diarization: nil, planner: .file,
                                           shouldPause: { flag.paused ? "Your Mac is busy" : nil })
        let began = Date()
        Task {
            try await Task.sleep(for: .milliseconds(300))
            flag.resume() // "Continue Anyway"
        }
        let result = try await transcriber.run { reports.add($0.pausedReason) }
        #expect(Date().timeIntervalSince(began) < 3)
        #expect(result.segments.map(\.text) == [" Devam."])
        let all = reports.all
        #expect(all.first == "Your Mac is busy")
        #expect(all.dropFirst().first == .some(nil)) // resumed, reported before any text
    }
}
