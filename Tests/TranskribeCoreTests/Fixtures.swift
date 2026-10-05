import Foundation
@testable import TranskribeCore

enum Fixtures {
    static func transcript(
        title: String = "Weekly sync",
        segments: [Segment] = [
            Segment(start: 0, end: 2.5, text: "Merhaba, nasılsın?"),
            Segment(start: 2.5, end: 65.25, text: "İyiyim, teşekkürler."),
        ],
        tracks: [AudioTrack] = [AudioTrack(fileName: "audio.m4a")]
    ) -> Transcript {
        Transcript(
            id: UUID(),
            title: title,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 65.25,
            language: "tr",
            tracks: tracks,
            segments: segments,
            status: .done
        )
    }

    /// A fresh folder for one test. All of them are deleted when the test run ends.
    static func temporaryDirectory() throws -> URL {
        let url = runDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Throwaway settings for one test, deleted when the test run ends.
    static func temporaryDefaults() -> UserDefaults {
        let name = "transkribe-tests-\(UUID().uuidString)"
        removeAfterRun(defaultsNamed: name)
        return UserDefaults(suiteName: name)!
    }

    /// Deletes a settings domain a test created, once the run ends.
    static func removeAfterRun(defaultsNamed name: String) {
        _ = runDirectory
        defaultsLock.withLock { createdDefaults.append(name) }
    }

    private static let defaultsLock = NSLock()
    nonisolated(unsafe) private static var createdDefaults: [String] = []

    private static let runDirectory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranskribeTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        atexit {
            try? FileManager.default.removeItem(at: Fixtures.runDirectory)
            for name in Fixtures.defaultsLock.withLock({ Fixtures.createdDefaults }) {
                UserDefaults.standard.removePersistentDomain(forName: name)
                // Let the preferences daemon finish writing before the file is deleted, or it
                // puts an empty one back.
                CFPreferencesAppSynchronize(name as CFString)
                let plist = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/\(name).plist")
                try? FileManager.default.removeItem(at: plist)
            }
        }
        return url
    }()
}
