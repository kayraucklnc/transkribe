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

extension ModelFiles {
    /// Deletes models Transkribe no longer uses (and their markers) from `directory`, the app's
    /// own Models folder. Anything outside it is left alone. Returns the bytes freed.
    @discardableResult
    public static func removeRetired(_ models: [String] = EngineCatalog.retiredModels,
                                     in directory: URL = TranscriptionEngine.defaultModelsDirectory) -> Int64 {
        let manager = FileManager.default
        let root = directory.standardizedFileURL.path + "/"
        var freed: Int64 = 0
        for model in models {
            let marker = directory.appendingPathComponent("\(model).ready")
            var folders = [directory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model)")]
            if let saved = try? String(contentsOf: marker, encoding: .utf8) {
                folders.append(URL(fileURLWithPath: saved.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            for folder in folders where folder.standardizedFileURL.path.hasPrefix(root)
                && folder.lastPathComponent == model && manager.fileExists(atPath: folder.path) {
                freed += size(of: folder)
                try? manager.removeItem(at: folder)
            }
            for suffix in ["ready", "prepared"] {
                try? manager.removeItem(at: directory.appendingPathComponent("\(model).\(suffix)"))
            }
        }
        return freed
    }

    private static func size(of folder: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
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
