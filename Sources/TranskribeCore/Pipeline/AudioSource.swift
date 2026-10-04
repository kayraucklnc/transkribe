import Foundation

/// Audio that a `TrackTranscriber` reads in slices: either a finished file or a recording
/// that is still growing.
public protocol AudioSource: Sendable {
    /// True once no more audio will arrive. Check this before `availableDuration()`.
    var isComplete: Bool { get }
    func availableDuration() async throws -> TimeInterval
    func read(from start: TimeInterval, to end: TimeInterval) async throws -> [Float]
}

public struct FileAudioSource: AudioSource {
    public let url: URL
    public var isComplete: Bool { true }

    public init(url: URL) {
        self.url = url
    }

    public func availableDuration() async throws -> TimeInterval {
        try await AudioDecoder.duration(of: url)
    }

    public func read(from start: TimeInterval, to end: TimeInterval) async throws -> [Float] {
        try await AudioDecoder.decode(url: url, from: start, to: end)
    }
}

/// Reads the live 16 kHz copy a recording writes, until the recording is marked finished.
public final class LiveAudioSource: AudioSource, @unchecked Sendable {
    private let reader: PCMStore.Reader
    private let lock = NSLock()
    private var complete = false

    public init(url: URL) {
        reader = PCMStore.Reader(url: url)
    }

    public var isComplete: Bool { lock.withLock { complete } }

    public func markComplete() {
        lock.withLock { complete = true }
    }

    public func availableDuration() async throws -> TimeInterval {
        reader.duration
    }

    public func read(from start: TimeInterval, to end: TimeInterval) async throws -> [Float] {
        try reader.read(from: start, to: end)
    }
}
