import Foundation
import TranskribeCore

extension AppModel {
    /// Re-transcribes conversations at the best quality while the Mac has nothing else to do,
    /// one at a time. The upgraded text replaces the old one; names, "Me", summaries and chats stay.
    func startEnhancing() {
        enhanceTask?.cancel()
        enhanceTask = Task(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard let self, self.settings.enhanceWhenIdle, self.settings.completedOnboarding,
                      self.settings.quality != .best, !self.isRecording, self.queueTask == nil,
                      self.isIdleEnoughToEnhance(),
                      let next = self.transcripts.first(where: { $0.status == .done && ($0.quality ?? .balanced) != .best && !$0.segments.isEmpty })
                else { continue }
                await self.enhance(next)
            }
        }
    }

    /// Stricter than the pause check: on power, cool, and mostly idle.
    private func isIdleEnoughToEnhance() -> Bool {
        let reading = ResourceGovernor.currentReading()
        guard ResourceGovernor.pauseReason(for: reading) == nil, reading.isCharging || reading.batteryLevel == nil else { return false }
        return reading.loadAverage < Double(reading.cores) * 0.35
    }

    private func enhance(_ transcript: Transcript) async {
        let id = transcript.id
        enhancingID = id
        defer { enhancingID = nil }
        let engine = Self.makeEngine(settings: settings, quality: .best, european: european)
        do {
            try await engine.prepare { _ in }
            let sources = transcript.tracks.map { track in
                (track, FileAudioSource(url: store.audioURL(for: transcript, track: track)) as AudioSource)
            }
            try await runPipeline(for: transcript, sources: sources, isLive: false, engine: engine, quality: .best, showsProgress: false)
        } catch {
            // Leave the existing transcript as it is; try again later.
        }
    }
}
