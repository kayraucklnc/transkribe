import Foundation

/// Transcribes one audio track in consecutive windows, keeping memory flat for any length and
/// reporting results as they are committed. Works the same for a 3-hour file and for a
/// recording that is still in progress.
public final class TrackTranscriber: @unchecked Sendable {
    public struct Progress: Sendable {
        /// Segments that are final, in track time.
        public var committed: [RawSegment]
        /// Text of the window currently being transcribed (not final yet).
        public var pending: [RawSegment]
        /// Everything before this point has been transcribed.
        public var committedUntil: TimeInterval
        public var availableDuration: TimeInterval
        /// Speaker turns found so far (empty when the track isn't diarized).
        public var turns: [SpeakerTurn]
        public var language: String?
        /// Set while transcription waits for the Mac to have resources to spare.
        public var pausedReason: String? = nil
    }

    public struct Result: Sendable {
        public var segments: [RawSegment]
        public var turns: [SpeakerTurn]
        public var language: String?
        public var languageWeights: [String: Int]
    }

    private let source: AudioSource
    private let engine: any SpeechEngine
    private let diarization: DiarizationStream?
    private let planner: WindowPlanner
    private let pollInterval: Duration
    /// Diarization is fed in pieces of this length so memory stays bounded.
    private let diarizationPiece: TimeInterval
    /// Returns a reason to hold off before the next window, or nil to continue.
    private let shouldPause: @Sendable () -> String?

    public init(
        source: AudioSource,
        engine: any SpeechEngine,
        diarization: DiarizationStream?,
        planner: WindowPlanner,
        pollInterval: Duration = .seconds(1),
        diarizationPiece: TimeInterval = 120,
        shouldPause: @escaping @Sendable () -> String? = { nil }
    ) {
        self.source = source
        self.engine = engine
        self.diarization = diarization
        self.planner = planner
        self.pollInterval = pollInterval
        self.diarizationPiece = diarizationPiece
        self.shouldPause = shouldPause
    }

    /// Runs until the source is complete and fully transcribed. `resume` continues an
    /// interrupted job: its segments are kept and transcription restarts after them.
    public func run(
        resume: [RawSegment] = [],
        resumeUntil: TimeInterval = 0,
        onProgress: @escaping @Sendable (Progress) async -> Void
    ) async throws -> Result {
        var committed = resume
        var committedUntil = resumeUntil
        var diarizedUntil: TimeInterval = 0
        var languageWeights: [String: Int] = [:]

        while true {
            try Task.checkCancellation()
            let complete = source.isComplete
            let available = try await source.availableDuration()

            if let diarization {
                while diarizedUntil < available - 0.01 {
                    let end = min(available, diarizedUntil + diarizationPiece)
                    try diarization.append(try await source.read(from: diarizedUntil, to: end))
                    diarizedUntil = end
                }
            }

            if let reason = shouldPause() {
                // Resources are tight: wait (recording continues), then pick up exactly here.
                await onProgress(Progress(committed: committed, pending: [], committedUntil: committedUntil,
                                          availableDuration: available, turns: diarization?.turns() ?? [],
                                          language: nil, pausedReason: reason))
                try await Task.sleep(for: .seconds(10))
                continue
            }

            guard let window = planner.window(committed: committedUntil, available: available, sourceComplete: complete) else {
                if complete { break }
                try await Task.sleep(for: pollInterval)
                continue
            }

            let samples = try await source.read(from: window.start, to: window.end)
            let snapshot = (committed: committed, until: committedUntil)
            let output = try await engine.transcribe(samples: samples) { [diarization] partial in
                let pending = partial.map { Self.shift($0, by: window.start) }
                Task {
                    await onProgress(Progress(committed: snapshot.committed, pending: pending,
                                              committedUntil: snapshot.until, availableDuration: available,
                                              turns: diarization?.turns() ?? [], language: nil))
                }
            }
            languageWeights = TranscriptionEngine.merge(languageWeights, output.languageWeights)
            let filled = try await fillGaps(in: output.segments, samples: samples)
            let shifted = filled.map { Self.shift($0, by: window.start) }
            let result = planner.commit(shifted, in: window, previous: committed.last)
            committed += result.segments
            committedUntil = result.committedUntil
            await onProgress(Progress(committed: committed, pending: [], committedUntil: committedUntil,
                                      availableDuration: available, turns: diarization?.turns() ?? [],
                                      language: TranscriptionEngine.dominantLanguage(weights: languageWeights)))
        }

        try diarization?.finish()
        return Result(segments: committed, turns: diarization?.turns() ?? [],
                      language: TranscriptionEngine.dominantLanguage(weights: languageWeights),
                      languageWeights: languageWeights)
    }

    /// Re-transcribes stretches where the audio has speech but no text came out, so a sentence
    /// the recognizer skipped isn't lost.
    private func fillGaps(in segments: [RawSegment], samples: [Float]) async throws -> [RawSegment] {
        let rate = AudioDecoder.sampleRate
        let gaps = GapFinder.uncovered(speech: GapFinder.speechRegions(in: samples), segments: segments)
        guard !gaps.isEmpty else { return segments }
        var result = segments
        for gap in gaps.prefix(8) {
            try Task.checkCancellation()
            let start = max(0, gap.lowerBound - 0.3), end = min(Double(samples.count) / rate, gap.upperBound + 0.3)
            let clip = Array(samples[Int(start * rate)..<min(samples.count, Int(end * rate))])
            guard let redo = try? await engine.transcribe(samples: clip, onSegments: { _ in }) else { continue }
            let found = redo.segments
                .map { Self.shift($0, by: start) }
                .filter { $0.text.split(whereSeparator: \.isWhitespace).count >= 2 && !Hallucinations.isHallucination($0.text) }
                .filter { candidate in !result.contains { $0.start < candidate.end && candidate.start < $0.end } }
            result += found
        }
        return result.sorted { $0.start < $1.start }
    }

    static func shift(_ segment: RawSegment, by offset: TimeInterval) -> RawSegment {
        RawSegment(
            start: segment.start + offset,
            end: segment.end + offset,
            text: segment.text,
            words: segment.words.map { Word(start: $0.start + offset, end: $0.end + offset, text: $0.text) },
            speaker: segment.speaker
        )
    }
}
