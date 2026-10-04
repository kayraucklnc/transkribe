import Foundation
import WhisperKit

/// Runs Whisper locally via WhisperKit (Core ML). Downloads the model once, then works offline.
public actor TranscriptionEngine {
    /// Whisper large-v3 turbo, quantized: multilingual (Turkish included), ~630 MB on disk.
    public static let defaultModel = "openai_whisper-large-v3-v20240930_turbo_632MB"

    public enum Preparation: Sendable, Equatable {
        case downloading(Double)
        /// `firstTime` is true while Core ML optimizes the model for this Mac (minutes, once).
        case loading(firstTime: Bool)
        case ready
    }

    /// Languages the user speaks. Detection only chooses among these, so a quiet or noisy
    /// stretch is never mistaken for a third language, and decoding with a fixed language
    /// makes Whisper's repetition loops rarer. Empty = any language.
    public static let supportedLanguages: Set<String> = ["en", "tr", "it"]

    public struct Output: Sendable {
        public var segments: [RawSegment]
        public var language: String?
        /// Characters of text per detected language, to pick the language of a long recording.
        public var languageWeights: [String: Int] = [:]
    }

    private let model: String
    private let modelsDirectory: URL
    private var loaded: LoadedModel?
    private var preparing: Task<LoadedModel, Error>?
    private var isRunning = false
    /// Last language confirmed by detection, used for stretches too short or unclear to tell.
    private var lastLanguage: String?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(model: String = TranscriptionEngine.defaultModel, modelsDirectory: URL = TranscriptionEngine.defaultModelsDirectory) {
        self.model = model
        self.modelsDirectory = modelsDirectory
    }

    public static var defaultModelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Transkribe/Models", isDirectory: true)
    }

    /// Downloads (first run only) and loads the model. Safe to call repeatedly and concurrently.
    public func prepare(onProgress: @escaping @Sendable (Preparation) -> Void = { _ in }) async throws {
        _ = try await model(onProgress: onProgress)
    }

    private func model(onProgress: @escaping @Sendable (Preparation) -> Void = { _ in }) async throws -> LoadedModel {
        if let loaded { return loaded }
        if let preparing { return try await preparing.value }

        let task = Task { [model, modelsDirectory] in
            let folder = try await Self.modelFolder(model: model, in: modelsDirectory, onProgress: onProgress)
            let preparedMarker = modelsDirectory.appendingPathComponent("\(model).prepared")
            onProgress(.loading(firstTime: !FileManager.default.fileExists(atPath: preparedMarker.path)))
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                // Keep the tokenizer next to the model; the default (~/Documents) triggers a privacy prompt.
                tokenizerFolder: modelsDirectory,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let whisper = try await WhisperKit(config)
            FileManager.default.createFile(atPath: preparedMarker.path, contents: nil)
            return LoadedModel(whisper: whisper)
        }
        preparing = task
        do {
            let model = try await task.value
            loaded = model
            preparing = nil
            onProgress(.ready)
            return model
        } catch {
            preparing = nil
            throw error
        }
    }

    /// Transcribes 16 kHz mono samples, auto-detecting the spoken language.
    /// `onSegments` receives the segments found so far (sorted by time) as decoding progresses.
    public func transcribe(
        samples: [Float],
        onSegments: @escaping @Sendable ([RawSegment]) -> Void = { _ in }
    ) async throws -> Output {
        // The actor can interleave at `await`s; WhisperKit must only run one job at a time
        // (a live recording and the import queue may both be transcribing).
        await acquire()
        defer { release() }
        return try await runTranscription(samples: samples, onSegments: onSegments)
    }

    private func acquire() async {
        guard isRunning else {
            isRunning = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    private func runTranscription(
        samples: [Float],
        onSegments: @escaping @Sendable ([RawSegment]) -> Void
    ) async throws -> Output {
        let whisper = try await model().whisper
        guard !samples.isEmpty else { return Output(segments: [], language: nil) }

        let collected = SegmentCollector(onChange: onSegments)
        whisper.segmentDiscoveryCallback = { segments in
            collected.add(segments.map { RawSegment(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.text) })
        }
        defer { whisper.segmentDiscoveryCallback = nil }

        let language = await chooseLanguage(whisper, samples: samples)
        let options = Self.options(language: language, strict: false)
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()

        var segments = results
            .flatMap(\.segments)
            .map(Self.raw)
            .sorted { $0.start < $1.start }
        segments = try await repairLoops(segments, samples: samples, whisper: whisper, language: language ?? results.first?.language)
        let weights = results.reduce(into: [String: Int]()) { $0[language ?? $1.language, default: 0] += $1.text.count }
        return Output(segments: segments, language: Self.dominantLanguage(weights: weights), languageWeights: weights)
    }

    // MARK: - Decoding

    static func options(language: String?, strict: Bool) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            wordTimestamps: true,
            // Stricter thresholds make Whisper retry (at higher temperature) sooner when it
            // starts repeating itself; used when re-doing a passage that looped.
            compressionRatioThreshold: strict ? 1.8 : 2.4,
            logProbThreshold: strict ? -0.8 : -1.0,
            chunkingStrategy: .vad
        )
    }

    static func raw(_ segment: TranscriptionSegment) -> RawSegment {
        RawSegment(
            start: TimeInterval(segment.start),
            end: TimeInterval(segment.end),
            text: segment.text,
            words: (segment.words ?? []).map { Word(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.word) }
        )
    }

    /// Picks the language by asking Whisper about up to three 30-second samples of the audio and
    /// voting among supported languages. Short or unclear audio (a quick "mm", noise) often comes
    /// back as some other language; it then reuses the last language this engine settled on.
    private func chooseLanguage(_ whisper: WhisperKit, samples: [Float]) async -> String? {
        guard !Self.supportedLanguages.isEmpty else { return nil }
        let slice = Int(AudioDecoder.sampleRate) * 30
        let starts = samples.count <= slice ? [0] : [0, (samples.count - slice) / 2, samples.count - slice]
        var votes: [String] = []
        for start in starts where samples.count > start {
            let piece = Array(samples[start..<min(samples.count, start + slice)])
            if let detection = try? await whisper.detectLangauge(audioArray: piece) { votes.append(detection.language) }
        }
        let chosen = Self.vote(votes, fallback: lastLanguage)
        if let chosen { lastLanguage = chosen }
        return chosen
    }

    /// The supported language most samples agreed on; otherwise `fallback`; otherwise the first
    /// supported language in a stable order.
    static func vote(_ detected: [String], fallback: String?) -> String? {
        let counts = Dictionary(detected.filter(supportedLanguages.contains).map { ($0, 1) }, uniquingKeysWith: +)
        if let best = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key {
            return best
        }
        return fallback ?? supportedLanguages.sorted().first
    }

    /// Whisper sometimes gets stuck repeating a syllable or word over real speech, depending on
    /// where a chunk happens to start. Re-transcribing just that passage on its own, with a fixed
    /// language and stricter loop detection, recovers the actual words.
    private func repairLoops(_ segments: [RawSegment], samples: [Float], whisper: WhisperKit, language: String?) async throws -> [RawSegment] {
        var result = segments
        let rate = AudioDecoder.sampleRate
        for index in result.indices.reversed() where RepetitionFilter.isLoop(result[index].text)
            || RepetitionFilter.isLoop(result[index].words.map(\.text).joined()) {
            let segment = result[index]
            let start = max(0, segment.start - 1), end = min(Double(samples.count) / rate, segment.end + 1)
            guard end - start > 0.5 else { continue }
            let clip = Array(samples[Int(start * rate)..<min(samples.count, Int(end * rate))])
            guard let redo = try? await whisper.transcribe(audioArray: clip, decodeOptions: Self.options(language: language, strict: true)) else { continue }
            try Task.checkCancellation()
            let replacement = redo.flatMap(\.segments).map(Self.raw).map { TrackTranscriber.shift($0, by: start) }
            let text = replacement.map(\.text).joined(separator: " ")
            guard !replacement.isEmpty, !RepetitionFilter.isLoop(text) else { continue }
            result.replaceSubrange(index...index, with: replacement)
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: - Helpers

    /// The language with the most transcribed text. Counting chunks instead would let short or
    /// silent stretches (which Whisper tends to label English) outvote the actual conversation.
    public static func dominantLanguage(weights: [String: Int]) -> String? {
        weights.filter { !$0.key.isEmpty && $0.value > 0 }
            .max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    public static func merge(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] {
        a.merging(b, uniquingKeysWith: +)
    }

    public static func dominantLanguage(_ languages: [String]) -> String? {
        let counts = Dictionary(languages.filter { !$0.isEmpty }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    private static func modelFolder(
        model: String,
        in directory: URL,
        onProgress: @escaping @Sendable (Preparation) -> Void
    ) async throws -> URL {
        let marker = directory.appendingPathComponent("\(model).ready")
        if let saved = try? String(contentsOf: marker, encoding: .utf8),
           FileManager.default.fileExists(atPath: saved) {
            return URL(fileURLWithPath: saved)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        onProgress(.downloading(0))
        let folder = try await WhisperKit.download(variant: model, downloadBase: directory) { progress in
            onProgress(.downloading(progress.fractionCompleted))
        }
        try folder.path.write(to: marker, atomically: true, encoding: .utf8)
        return folder
    }
}

/// WhisperKit isn't Sendable; the engine actor only ever uses it from one transcription at a time.
private final class LoadedModel: @unchecked Sendable {
    let whisper: WhisperKit

    init(whisper: WhisperKit) {
        self.whisper = whisper
    }
}

/// Thread-safe accumulator for segments reported from WhisperKit's concurrent workers.
private final class SegmentCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var segments: [RawSegment] = []
    private let onChange: @Sendable ([RawSegment]) -> Void

    init(onChange: @escaping @Sendable ([RawSegment]) -> Void) {
        self.onChange = onChange
    }

    func add(_ newSegments: [RawSegment]) {
        let snapshot: [RawSegment] = lock.withLock {
            segments.append(contentsOf: newSegments)
            segments.sort { $0.start < $1.start }
            return segments
        }
        onChange(snapshot)
    }
}
