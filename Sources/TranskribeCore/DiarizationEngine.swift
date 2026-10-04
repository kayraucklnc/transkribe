import CoreML
import FluidAudio
import Foundation

/// Finds who spoke when, on-device. Uses LS-EEND (end-to-end neural diarization) trained on
/// phone conversations, which follows quick back-and-forth ("…acaba?" / "Evet buyurun.")
/// far better than clustering-based pipelines. Downloads its model once.
public actor DiarizationEngine {
    /// In automatic mode, "speakers" with less talk time than this are treated as noise.
    static let minimumShare = 0.08

    private let modelsDirectory: URL
    private var loading: Task<LoadedDiarizer, Error>?

    public init(modelsDirectory: URL = TranscriptionEngine.defaultModelsDirectory) {
        self.modelsDirectory = modelsDirectory
    }

    /// Speaker turns for 16 kHz mono samples. Speakers are numbered from 1 in order of
    /// first appearance. Pass `speakerCount` when the user knows how many people talked.
    public func turns(samples: [Float], speakerCount: Int? = nil) async throws -> [SpeakerTurn] {
        guard !samples.isEmpty else { return [] }
        let diarizer = try await model().diarizer
        let timeline = try diarizer.processComplete(samples, sourceSampleRate: AudioDecoder.sampleRate, keepingEnrolledSpeakers: false)
        try Task.checkCancellation()
        let raw = timeline.speakers.values.flatMap { speaker in
            speaker.finalizedSegments.map {
                SpeakerTurn(start: TimeInterval($0.startTime), end: TimeInterval($0.endTime), speaker: $0.speakerIndex)
            }
        }
        return Self.renumbered(Self.select(raw, speakerCount: speakerCount))
    }

    /// Keeps the `speakerCount` most talkative speakers, or in automatic mode everyone
    /// with a meaningful share of the conversation. Words from dropped speakers are later
    /// attributed to the nearest remaining turn.
    static func select(_ turns: [SpeakerTurn], speakerCount: Int?) -> [SpeakerTurn] {
        let seconds = talkTime(turns)
        let ranked = seconds.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
        let keep = Set(ranked.prefix(speakerCount ?? significantSpeakerCount(turns)))
        return turns.filter { keep.contains($0.speaker) }
    }

    /// Number of speakers holding at least `minimumShare` of the talk time (at least 1).
    static func significantSpeakerCount(_ turns: [SpeakerTurn]) -> Int {
        let seconds = talkTime(turns)
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return 1 }
        return max(1, seconds.values.filter { $0 / total >= minimumShare }.count)
    }

    /// Sorts turns and renumbers speakers 1, 2, 3… by first appearance.
    static func renumbered(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
        var mapping: [Int: Int] = [:]
        return turns.sorted { $0.start < $1.start }.map { turn in
            let id = mapping[turn.speaker] ?? {
                let next = mapping.count + 1
                mapping[turn.speaker] = next
                return next
            }()
            return SpeakerTurn(start: turn.start, end: turn.end, speaker: id)
        }
    }

    private static func talkTime(_ turns: [SpeakerTurn]) -> [Int: TimeInterval] {
        turns.reduce(into: [:]) { $0[$1.speaker, default: 0] += max(0, $1.end - $1.start) }
    }

    // MARK: - Model

    /// Concurrent callers share one load; a failed load is retried next time.
    private func model() async throws -> LoadedDiarizer {
        if let loading { return try await loading.value }
        let directory = modelsDirectory.appendingPathComponent("FluidAudio", isDirectory: true)
        let task = Task {
            let diarizer = LSEENDDiarizer()
            try await diarizer.initialize(variant: .callhome, stepSize: .step500ms, cacheDirectory: directory)
            return LoadedDiarizer(diarizer: diarizer)
        }
        loading = task
        do {
            return try await task.value
        } catch {
            loading = nil
            throw error
        }
    }
}

/// The diarizer keeps per-run state; the engine actor only ever runs one job at a time.
private final class LoadedDiarizer: @unchecked Sendable {
    let diarizer: LSEENDDiarizer

    init(diarizer: LSEENDDiarizer) {
        self.diarizer = diarizer
    }
}
