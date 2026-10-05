import Foundation

/// A plain 16 kHz mono 16-bit file written alongside a live recording. Unlike the compressed
/// .m4a, it can be read while it is still being written, which is what lets transcription
/// keep up with an ongoing conversation.
public enum PCMStore {
    public static let sampleRate: Double = 16_000
    static let bytesPerSample = 2

    public final class Writer: @unchecked Sendable {
        private let handle: FileHandle
        private let lock = NSLock()

        public init(url: URL) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
        }

        deinit {
            try? handle.close()
        }

        public func append(_ samples: [Float]) throws {
            guard !samples.isEmpty else { return }
            var data = Data(count: samples.count * bytesPerSample)
            data.withUnsafeMutableBytes { raw in
                let out = raw.bindMemory(to: Int16.self)
                for (index, sample) in samples.enumerated() {
                    out[index] = Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian
                }
            }
            try lock.withLock { try handle.write(contentsOf: data) }
        }
    }

    public struct Reader: Sendable {
        public let url: URL

        public init(url: URL) {
            self.url = url
        }

        public var duration: TimeInterval {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return Double(size / bytesPerSample) / sampleRate
        }

        public func read(from start: TimeInterval, to end: TimeInterval) throws -> [Float] {
            let available = Int(duration * sampleRate)
            let first = max(0, min(available, Int((start * sampleRate).rounded())))
            let last = max(first, min(available, Int((end * sampleRate).rounded())))
            guard last > first else { return [] }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(first * bytesPerSample))
            let data = try handle.read(upToCount: (last - first) * bytesPerSample) ?? Data()
            return data.withUnsafeBytes { raw in
                raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / Float(Int16.max) }
            }
        }
    }
}
