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

    /// The speaker model's `turns` regrouped by how the voices sound, so every person gets their
    /// own number however many there are (see `VoiceSeparator`). `read` gives the track's 16 kHz
    /// mono audio between two times.
    public func separateVoices(turns: [SpeakerTurn], speakerCount: Int? = nil,
                               threshold: Float = VoiceSeparator.defaultThreshold,
                               smoothing: VoiceSeparator.Smoothing = .standard,
                               read: @Sendable (TimeInterval, TimeInterval) async throws -> [Float]) async throws -> [SpeakerTurn] {
        guard !turns.isEmpty else { return turns }
        let manager = try await loaded()
        let windows = VoiceSeparator.windows(for: turns)
        var voiceprints: [[Float]?] = []
        voiceprints.reserveCapacity(windows.count)
        for window in windows {
            try Task.checkCancellation()
            guard window.wantsVoiceprint else { voiceprints.append(nil); continue }
            let samples = try await read(window.start, window.end)
            let embedding = samples.isEmpty ? nil : try manager.extractSpeakerEmbedding(from: samples)
            voiceprints.append(embedding.flatMap { manager.validateEmbedding($0) ? $0 : nil })
        }
        return VoiceSeparator.separate(turns: turns, windows: windows, voiceprints: voiceprints,
                                       speakerCount: speakerCount, threshold: threshold, smoothing: smoothing)
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
