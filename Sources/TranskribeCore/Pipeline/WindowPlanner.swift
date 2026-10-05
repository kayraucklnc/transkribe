import Foundation

/// Decides which slice of audio to transcribe next, and which results are safe to keep.
///
/// Audio is processed in windows. Segments that end close to a window's edge may be cut
/// mid-word, so they are held back and the next window starts exactly where the last kept
/// segment ended. That way consecutive batches never leave a gap and never cut a sentence.
public struct WindowPlanner: Sendable {
    public struct Window: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        /// The last window of a finished source: everything in it is kept.
        public var isFinal: Bool

        public init(start: TimeInterval, end: TimeInterval, isFinal: Bool) {
            self.start = start
            self.end = end
            self.isFinal = isFinal
        }
    }

    public struct Commit: Equatable, Sendable {
        public var segments: [RawSegment]
        public var committedUntil: TimeInterval
    }

    /// Live audio is only transcribed once at least this much new audio has arrived.
    public var minimumWindow: TimeInterval
    /// Bounds memory and latency for long files.
    public var maximumWindow: TimeInterval
    /// Segments ending within this distance of a non-final window's end are re-done next time.
    public var tailGuard: TimeInterval

    public init(minimumWindow: TimeInterval = 30, maximumWindow: TimeInterval = 300, tailGuard: TimeInterval = 5) {
        self.minimumWindow = minimumWindow
        self.maximumWindow = maximumWindow
        self.tailGuard = tailGuard
    }

    public static let live = WindowPlanner(minimumWindow: 30, maximumWindow: 120, tailGuard: 5)
    public static let file = WindowPlanner(minimumWindow: 30, maximumWindow: 600, tailGuard: 5)

    public func window(committed: TimeInterval, available: TimeInterval, sourceComplete: Bool) -> Window? {
        let pending = available - committed
        guard pending > (sourceComplete ? 0.25 : minimumWindow) else { return nil }
        let end = min(available, committed + maximumWindow)
        return Window(start: committed, end: end, isFinal: sourceComplete && end >= available)
    }

    /// `segments` are in absolute time. `previous` is the last segment kept so far, used to drop a
    /// sentence that both sides of a batch boundary transcribed.
    public func commit(_ segments: [RawSegment], in window: Window, previous: RawSegment? = nil) -> Commit {
        let fresh = dropSeamDuplicates(segments, previous: previous)
        if window.isFinal {
            return Commit(segments: fresh, committedUntil: window.end)
        }
        let cutoff = window.end - tailGuard
        let kept = fresh.filter { $0.end <= cutoff }
        if let last = kept.last {
            return Commit(segments: kept, committedUntil: max(window.start, last.end))
        }
        if fresh.isEmpty {
            // Nothing was said; move on without re-transcribing the silence forever.
            return Commit(segments: [], committedUntil: max(window.start, cutoff))
        }
        if window.end - window.start >= maximumWindow - 0.001 {
            // A maximum-length window must always make progress.
            return Commit(segments: fresh, committedUntil: max(window.start, fresh.last!.end))
        }
        return Commit(segments: [], committedUntil: window.start)
    }

    private func dropSeamDuplicates(_ segments: [RawSegment], previous: RawSegment?) -> [RawSegment] {
        guard let previous else { return segments }
        let previousText = TranscriptSearch.normalize(previous.text).trimmingCharacters(in: .whitespacesAndNewlines)
        var result = segments
        while let first = result.first,
              first.start - previous.end < 2,
              TranscriptSearch.normalize(first.text).trimmingCharacters(in: .whitespacesAndNewlines) == previousText {
            result.removeFirst()
        }
        return result
    }
}
