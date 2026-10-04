import AVFoundation
import Observation
import TranskribeCore

/// Plays a transcript's tracks together (mic + system mixed) and reports the playhead.
@MainActor
@Observable
final class PlayerController {
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var loadedID: Transcript.ID?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var rateObserver: NSKeyValueObservation?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.currentTime = time.seconds.isFinite ? time.seconds : 0 }
        }
        rateObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    func load(_ transcript: Transcript, store: TranscriptStore) async {
        guard loadedID != transcript.id else { return }
        player.pause()
        loadedID = transcript.id
        currentTime = 0
        duration = transcript.duration
        let composition = AVMutableComposition()
        for track in transcript.tracks {
            let asset = AVURLAsset(url: store.audioURL(for: transcript, track: track))
            guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
                  let range = try? await source.load(.timeRange),
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try? destination.insertTimeRange(range, of: source, at: CMTime(seconds: track.offset, preferredTimescale: 600))
        }
        guard loadedID == transcript.id else { return }
        player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.1 { seek(to: 0) }
            player.play()
        }
    }

    func play(from time: TimeInterval) {
        seek(to: time)
        player.play()
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedID = nil
    }
}
