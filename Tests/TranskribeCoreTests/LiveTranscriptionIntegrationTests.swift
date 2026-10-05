import Foundation
import Testing
@testable import TranskribeCore

/// Real-model checks for batched transcription. Opt-in like the other integration tests.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_INTEGRATION"] == "1"), .serialized)
struct LiveTranscriptionIntegrationTests {
    /// Distinct sentences, each with one keyword that should appear exactly once in the result.
    static let lines: [(keyword: String, sentence: String)] = [
        ("apples", "We picked fresh apples at the farm on Saturday morning."),
        ("bicycle", "My brother finally repaired his old bicycle last week."),
        ("candles", "The restaurant lit tall candles on every single table."),
        ("dolphins", "Off the coast we watched a group of dolphins jumping."),
        ("elevator", "The elevator in our office broke down again today."),
        ("forest", "They built a small cabin at the edge of the forest."),
        ("guitar", "She practices the guitar for an hour every evening."),
        ("harbor", "Fishing boats were returning to the harbor at sunset."),
        ("island", "Next summer we want to rent a house on a quiet island."),
        ("jacket", "Don't forget your warm jacket, it will be cold tonight."),
        ("kettle", "Put the kettle on and we can talk about the budget."),
        ("lantern", "Grandpa still keeps an old oil lantern in the garage."),
        ("mountain", "The hike to the top of the mountain took six hours."),
        ("notebook", "I wrote every idea from the meeting in my notebook."),
        ("oranges", "The market sells the sweetest oranges in the city."),
        ("piano", "Their daughter played the piano at the school concert."),
        ("river", "A narrow wooden bridge crosses the river near town."),
        ("satellite", "The new weather satellite launches early next month."),
        ("tomatoes", "We grow tomatoes and peppers on the small balcony."),
        ("umbrella", "Someone left a bright yellow umbrella on the train."),
    ]

    /// About 90 seconds of speech from two alternating voices.
    private func speech() async throws -> [Float] {
        var samples: [Float] = []
        for (index, line) in Self.lines.enumerated() {
            let url = try Fixtures.temporaryDirectory().appendingPathComponent("s\(index).aiff")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", index.isMultiple(of: 2) ? "Samantha" : "Daniel", "-o", url.path, line.sentence]
            try process.run()
            process.waitUntilExit()
            samples += try await AudioDecoder.decode(url: url)
            samples += [Float](repeating: 0, count: 6_000)
        }
        return samples
    }

    private func occurrences(in segments: [RawSegment]) -> [String: Int] {
        let text = TranscriptSearch.normalize(segments.map(\.text).joined(separator: " "))
        return Dictionary(uniqueKeysWithValues: Self.lines.map { line in
            (line.keyword, text.components(separatedBy: line.keyword).count - 1)
        })
    }

    @Test func liveBatchesHaveNoGapsOrDuplicates() async throws {
        let samples = try await speech()
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("live.pcm")
        let writer = try PCMStore.Writer(url: url)
        let source = LiveAudioSource(url: url)

        // Simulate a recording: 4 seconds of audio arrive every 0.25 seconds (16x real time).
        let feeder = Task {
            let piece = 16_000 * 4
            for start in stride(from: 0, to: samples.count, by: piece) {
                try writer.append(Array(samples[start..<min(samples.count, start + piece)]))
                try await Task.sleep(for: .milliseconds(250))
            }
            source.markComplete()
        }

        let transcriber = TrackTranscriber(source: source, engine: TranscriptionIntegrationTests.engine,
                                           diarization: try await TranscriptionIntegrationTests.diarizer.makeStream(),
                                           planner: .live, pollInterval: .milliseconds(200))
        let updates = UpdateCounter()
        let result = try await transcriber.run { progress in
            if progress.pending.isEmpty { await updates.increment() }
        }
        try await feeder.value

        let counts = occurrences(in: result.segments)
        print("BATCHES", await updates.value, "COUNTS", counts.filter { $0.value != 1 })
        #expect(await updates.value >= 2, "audio should be committed in several batches")
        #expect(counts.values.allSatisfy { $0 == 1 }, "every sentence exactly once: \(counts.filter { $0.value != 1 })")
        #expect(zip(result.segments, result.segments.dropFirst()).allSatisfy { $0.start <= $1.start })
        #expect(Set(result.turns.map(\.speaker)).count == 2)
    }

    @Test func longFilesAreProcessedInWindows() async throws {
        let samples = try await speech()
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("long.pcm")
        try PCMStore.Writer(url: url).append(samples)
        let source = LiveAudioSource(url: url)
        source.markComplete()

        let small = WindowPlanner(minimumWindow: 30, maximumWindow: 40, tailGuard: 5)
        let transcriber = TrackTranscriber(source: source, engine: TranscriptionIntegrationTests.engine,
                                           diarization: nil, planner: small)
        let result = try await transcriber.run { _ in }
        let counts = occurrences(in: result.segments)
        #expect(counts.values.allSatisfy { $0 == 1 }, "\(counts.filter { $0.value != 1 })")
    }
}

actor UpdateCounter {
    var value = 0
    func increment() { value += 1 }
}
