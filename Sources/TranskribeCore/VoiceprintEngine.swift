import FluidAudio
import Foundation

/// Turns clips of one person talking into a voiceprint, on-device. Downloads a small
/// speaker-embedding model once.
public actor VoiceprintEngine {
    private let modelsDirectory: URL
    private var manager: DiarizerManager?

    public init(modelsDirectory: URL = TranscriptionEngine.defaultModelsDirectory) {
        self.modelsDirectory = modelsDirectory
    }

    /// One voiceprint from several clips of the same speaker (16 kHz mono), or nil if none was usable.
    public func voiceprint(clips: [[Float]]) async throws -> [Float]? {
        let manager = try await loaded()
        var learned: [Float]?
        var count = 0
        for clip in clips where clip.count >= Int(AudioDecoder.sampleRate * VoiceClips.minimumLength) {
            try Task.checkCancellation()
            let embedding = try manager.extractSpeakerEmbedding(from: clip)
            guard manager.validateEmbedding(embedding) else { continue }
            learned = Voiceprint.merge(learned, weight: count, with: embedding)
            count += 1
        }
        return learned
    }

    private func loaded() async throws -> DiarizerManager {
        if let manager { return manager }
        let directory = modelsDirectory.appendingPathComponent("FluidAudio", isDirectory: true)
        let models = try await DiarizerModels.downloadIfNeeded(to: directory)
        let manager = DiarizerManager()
        manager.initialize(models: models)
        self.manager = manager
        return manager
    }
}
