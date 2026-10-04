import AppKit
import UniformTypeIdentifiers

/// Turns drag-and-drop, paste and the Open panel into file URLs for `AppModel.importFiles`.
enum FileImport {
    static let acceptedTypes: [UTType] = [.fileURL, .audio, .audiovisualContent]
    private static let mediaTypes: [UTType] = [.audio, .audiovisualContent]

    @MainActor
    static func presentOpenPanel(model: AppModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = mediaTypes
        panel.allowsMultipleSelection = true
        panel.message = "Choose audio or video to transcribe"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls)
    }

    /// Resolves item providers from a drop or paste. Handles plain files as well as
    /// file promises (e.g. dragging a recording out of Voice Memos).
    @MainActor
    static func handle(_ providers: [NSItemProvider], model: AppModel) -> Bool {
        let usable = providers.filter { provider in
            acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
        guard !usable.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in usable {
                if let url = await resolve(provider) { urls.append(url) }
            }
            model.importFiles(urls)
        }
        return true
    }

    private static func resolve(_ provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
        }
        let type = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return mediaTypes.contains { type.conforms(to: $0) }
        }
        guard let type else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                // The provided file is deleted when this callback returns, so keep a copy.
                continuation.resume(returning: url.flatMap(copyToTemporaryLocation))
            }
        }
    }

    private static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TranskribeDrops", isDirectory: true)
    }

    /// Promised-file drops are copied here; they're only needed until import finishes.
    static func removeTemporaryCopies() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    private static func copyToTemporaryLocation(_ url: URL) -> URL? {
        let folder = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
