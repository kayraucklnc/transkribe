import Foundation

/// Checks that a downloaded Whisper model is really all there: a download can report success
/// with a file missing, and loading it then fails with a cryptic Core ML error.
public enum ModelFiles {
    static let requiredParts = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    public static func isComplete(_ folder: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.appendingPathComponent("config.json").path) else { return false }
        return requiredParts.allSatisfy { part in
            let bundle = folder.appendingPathComponent("\(part).mlmodelc")
            return [bundle.appendingPathComponent("coremldata.bin"), bundle.appendingPathComponent("weights/weight.bin")]
                .allSatisfy { url in
                    let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    return size > 0
                }
        }
    }
}

/// One download per model at a time, however many engines ask for it.
actor ModelDownloads {
    static let shared = ModelDownloads()
    private var inFlight: [String: Task<URL, Error>] = [:]

    func folder(for key: String, download: @escaping @Sendable () async throws -> URL) async throws -> URL {
        if let task = inFlight[key] { return try await task.value }
        let task = Task { try await download() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}
