import Foundation
import os
import TranskribeCore

extension AppModel {
    private static let compactionLog = Logger(subsystem: "Transkribe", category: "Compaction")

    /// Shrinks the audio of conversations whose text is final, one at a time, in the background.
    /// Older conversations are done too, so the whole library gets smaller over time.
    func startCompacting() {
        compactTask?.cancel()
        compactTask = Task(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.nextToCompact() == nil ? 60 : 5))
                guard let self, self.settings.completedOnboarding, !self.isRecording, self.queueTask == nil,
                      self.enhancingID == nil, self.activity.isEmpty,
                      ResourceGovernor.currentPauseReason() == nil,
                      let next = self.nextToCompact()
                else { continue }
                await self.compact(next)
            }
        }
    }

    private func nextToCompact() -> Transcript? {
        transcripts.first { isSettled($0) && !compactionChecked.contains($0.id) }
    }

    /// Whether this conversation's audio has done its work: no pass at a better quality is still
    /// coming (it would want the original), nothing is running on it, and it isn't open in the player.
    func isSettled(_ transcript: Transcript) -> Bool {
        guard transcript.status == .done, transcript.upgradeQuality == nil,
              transcript.id != selection, transcript.id != liveRecordingID,
              transcript.id != transcribingID, transcript.id != enhancingID
        else { return false }
        // Mirrors the idle pass in `startEnhancing`: it redoes these at Best later.
        let owesIdlePass = settings.enhanceWhenIdle && settings.quality != .best
            && (transcript.quality ?? .balanced) != .best && !transcript.segments.isEmpty
        return !owesIdlePass
    }

    private func compact(_ transcript: Transcript) async {
        let id = transcript.id
        compactionChecked.insert(id) // once per launch, whatever happens
        var renamed: [(from: String, to: String, original: URL)] = []
        var saved: Int64 = 0
        for track in transcript.tracks {
            let url = store.audioURL(for: transcript, track: track)
            do {
                let result = try await Task.detached(priority: .background) { try await AudioCompactor.compact(url) }.value
                guard let result else { continue }
                saved += result.savedBytes
                if let original = result.original { renamed.append((track.fileName, result.fileName, original)) }
            } catch {
                Self.compactionLog.error("Left \(track.fileName, privacy: .public) as it was: \(error.localizedDescription, privacy: .public)")
            }
        }
        if !renamed.isEmpty, !pointTracks(of: id, at: renamed) {
            // Keep the originals: the conversation still points at them.
            for rename in renamed {
                try? FileManager.default.removeItem(at: rename.original.deletingLastPathComponent().appendingPathComponent(rename.to))
            }
            return
        }
        for rename in renamed { try? FileManager.default.removeItem(at: rename.original) }
        if saved > 0 {
            Self.compactionLog.info("Saved \(saved, privacy: .public) bytes on a conversation's audio")
        }
    }

    /// Points the conversation's tracks at their compact copies and saves it. False when it
    /// can't (deleted, opened in the player meanwhile, or the save failed).
    private func pointTracks(of id: Transcript.ID, at renamed: [(from: String, to: String, original: URL)]) -> Bool {
        guard let current = transcript(id) else { return false }
        guard selection != id else {
            compactionChecked.remove(id) // the player reads the original: try again once it's closed
            return false
        }
        var updated = current
        updated.tracks = current.tracks.map { track in
            guard let rename = renamed.first(where: { $0.from == track.fileName }) else { return track }
            var track = track
            track.fileName = rename.to
            return track
        }
        do {
            try store.save(updated)
        } catch {
            Self.compactionLog.error("Couldn't point a conversation at its compact audio: \(error.localizedDescription, privacy: .public)")
            return false
        }
        update(id, persist: false) { $0.tracks = updated.tracks }
        return true
    }
}
