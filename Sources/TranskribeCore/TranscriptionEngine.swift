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

    public struct Output: Sendable {
        public var segments: [RawSegment]
        public var language: String?
    }

    private let model: String
    private let modelsDirectory: URL
    private var loaded: LoadedModel?
    private var preparing: Task<LoadedModel, Error>?

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
        let whisper = try await model().whisper
        guard !samples.isEmpty else { return Output(segments: [], language: nil) }

        let collected = SegmentCollector(onChange: onSegments)
        whisper.segmentDiscoveryCallback = { segments in
            collected.add(segments.map { RawSegment(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.text) })
        }
        defer { whisper.segmentDiscoveryCallback = nil }

        let options = DecodingOptions(
            task: .transcribe,
            language: nil,
            temperatureFallbackCount: 3,
            detectLanguage: true,
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()

        let segments = results
            .flatMap(\.segments)
            .map { segment in
                RawSegment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: segment.text,
                    words: (segment.words ?? []).map { Word(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.word) }
                )
            }
            .sorted { $0.start < $1.start }
        return Output(segments: segments, language: Self.dominantLanguage(results.map(\.language)))
    }

    // MARK: - Helpers

    static func dominantLanguage(_ languages: [String]) -> String? {
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
