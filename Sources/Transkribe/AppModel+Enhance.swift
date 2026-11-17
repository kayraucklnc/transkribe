import Foundation
import TranskribeCore

extension AppModel {
    /// Redoes conversations at a better quality in the background, one at a time. The upgraded text
    /// replaces the old one; names, "Me", summaries and chats stay.
    ///
    /// Two kinds of work, first one first:
    /// - A recording transcribed quickly so it kept up live is redone at the chosen quality soon
    ///   after it ends (it still pauses when the Mac is hot, on low battery or busy).
    /// - With "Make transcripts even better", older ones are redone at Best while the Mac is idle.
    func startEnhancing() {
        enhanceTask?.cancel()
        enhanceTask = Task(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.owedUpgrade() == nil ? 45 : 5))
                guard let self, self.settings.completedOnboarding, !self.isRecording, self.queueTask == nil,
                      self.activity.isEmpty // e.g. a stopped recording's last minutes
                else { continue }
                if let (next, quality) = self.owedUpgrade() {
                    await self.enhance(next, to: quality)
                    continue
                }
                guard self.settings.enhanceWhenIdle, self.settings.quality != .best, self.isIdleEnoughToEnhance(),
                      let next = self.transcripts.first(where: { $0.status == .done && ($0.quality ?? .balanced) != .best && !$0.segments.isEmpty })
                else { continue }
                await self.enhance(next, to: .best)
            }
        }
    }

    /// The newest recording still owed its better pass, and the quality it's owed.
    private func owedUpgrade() -> (Transcript, TranscriptionQuality)? {
        for transcript in transcripts where transcript.status == .done && !transcript.segments.isEmpty
            && !failedUpgrades.contains(transcript.id) {
            if let quality = transcript.upgradeQuality { return (transcript, quality) }
        }
        return nil
    }

    /// Stricter than the pause check: on power, cool, and mostly idle.
    private func isIdleEnoughToEnhance() -> Bool {
        let reading = ResourceGovernor.currentReading()
        guard ResourceGovernor.pauseReason(for: reading) == nil, reading.isCharging || reading.batteryLevel == nil else { return false }
        return reading.loadAverage < Double(reading.cores) * 0.35
    }

    private func enhance(_ transcript: Transcript, to quality: TranscriptionQuality) async {
        let id = transcript.id
        enhancingID = id
        defer { enhancingID = nil }
        // The chosen quality's engine is usually loaded already; anything else is made for this pass.
        let engine = quality == settings.quality ? self.engine : Self.makeEngine(settings: settings, quality: quality, european: european)
        do {
            try await engine.prepare { _ in }
            let sources = transcript.tracks.map { track in
                (track, FileAudioSource(url: store.audioURL(for: transcript, track: track)) as AudioSource)
            }
            try await runPipeline(for: transcript, sources: sources, isLive: false, engine: engine, quality: quality, showsProgress: false)
        } catch is CancellationError {
            // A recording started: it comes back to this afterwards.
        } catch {
            // Leave the existing transcript as it is.
            failedUpgrades.insert(id)
        }
    }
}
