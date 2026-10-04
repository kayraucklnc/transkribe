import CoreML
import FluidAudio
import Foundation

/// Finds who spoke when, on-device. Uses LS-EEND (end-to-end neural diarization) trained on
/// phone conversations, which follows quick back-and-forth ("…acaba?" / "Evet buyurun.")
/// far better than clustering-based pipelines. Downloads its model once.
public actor DiarizationEngine {
    /// In automatic mode, "speakers" with less talk time than this are treated as noise.
    static let minimumShare = 0.08
    static let variant: LSEENDVariant = .callhome

    private let modelsDirectory: URL

    public init(modelsDirectory: URL = TranscriptionEngine.defaultModelsDirectory) {
        self.modelsDirectory = modelsDirectory
    }

    /// A streaming session: feed audio as it arrives and read turns at any time. Speaker
    /// identities stay consistent for the whole session, however long it runs.
    public func makeStream() async throws -> DiarizationStream {
        let directory = modelsDirectory.appendingPathComponent("FluidAudio", isDirectory: true)
        let model = try await LSEENDModel.loadFromHuggingFace(variant: Self.variant, stepSize: .step500ms, cacheDirectory: directory)
        let diarizer = LSEENDDiarizer()
        try diarizer.initialize(model: model)
        return DiarizationStream(diarizer: diarizer)
    }

    /// Speaker turns for complete 16 kHz mono audio. Pass `speakerCount` when the user
    /// knows how many people talked.
    public func turns(samples: [Float], speakerCount: Int? = nil) async throws -> [SpeakerTurn] {
        guard !samples.isEmpty else { return [] }
        let stream = try await makeStream()
        let piece = Int(AudioDecoder.sampleRate) * 60
        for start in stride(from: 0, to: samples.count, by: piece) {
            try Task.checkCancellation()
            try stream.append(Array(samples[start..<min(samples.count, start + piece)]))
        }
        try stream.finish()
        return stream.turns(speakerCount: speakerCount)
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

    static func talkTime(_ turns: [SpeakerTurn]) -> [Int: TimeInterval] {
        turns.reduce(into: [:]) { $0[$1.speaker, default: 0] += max(0, $1.end - $1.start) }
    }
}

/// One continuous diarization session over a single audio track.
public final class DiarizationStream: @unchecked Sendable {
    private let diarizer: LSEENDDiarizer
    private let lock = NSLock()
    private var finished = false

    init(diarizer: LSEENDDiarizer) {
        self.diarizer = diarizer
    }

    /// Appends the next 16 kHz mono samples (contiguous with what came before).
    public func append(_ samples: [Float]) throws {
        try lock.withLock {
            guard !finished, !samples.isEmpty else { return }
            try diarizer.addAudio(samples, sourceSampleRate: AudioDecoder.sampleRate)
            _ = try diarizer.process()
        }
    }

    /// Flushes the model; call once when the audio has ended.
    public func finish() throws {
        try lock.withLock {
            guard !finished else { return }
            finished = true
            _ = try diarizer.finalizeSession()
        }
    }

    /// Turns found so far, cleaned up and numbered 1, 2, 3… by first appearance.
    public func turns(speakerCount: Int? = nil) -> [SpeakerTurn] {
        let raw: [SpeakerTurn] = lock.withLock {
            diarizer.timeline.speakers.values.flatMap { speaker in
                speaker.finalizedSegments.map {
                    SpeakerTurn(start: TimeInterval($0.startTime), end: TimeInterval($0.endTime), speaker: $0.speakerIndex)
                }
            }
        }
        return DiarizationEngine.renumbered(DiarizationEngine.select(raw, speakerCount: speakerCount))
    }
}
