import CoreML
import FluidAudio
import Foundation

/// NVIDIA Parakeet (open source, runs on device): faster and more accurate than Whisper for
/// English, Italian and other European languages. Used automatically for those languages.
public actor ParakeetEngine {
    private let directory: URL
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    public init(modelsDirectory: URL = TranscriptionEngine.defaultModelsDirectory) {
        directory = modelsDirectory.appendingPathComponent("Parakeet", isDirectory: true)
    }

    public func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        _ = try await loaded(onProgress: onProgress)
    }

    public var isReady: Bool { manager != nil }

    public func transcribe(samples: [Float]) async throws -> [RawSegment] {
        let manager = try await loaded(onProgress: { _ in })
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &state)
        let tokens = (result.tokenTimings ?? []).map { (text: $0.token, start: $0.startTime, end: $0.endTime) }
        if tokens.isEmpty {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [RawSegment(start: 0, end: Double(samples.count) / AudioDecoder.sampleRate, text: text)]
        }
        return SegmentAssembly.fromTokens(tokens)
    }

    private func loaded(onProgress: @escaping @Sendable (Double) -> Void) async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task { [directory] in
            let models = try await AsrModels.downloadAndLoad(to: directory, version: .ultra) { progress in
                onProgress(progress.fractionCompleted)
            }
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loading = task
        do {
            let ready = try await task.value
            manager = ready
            return ready
        } catch {
            loading = nil
            throw error
        }
    }
}
