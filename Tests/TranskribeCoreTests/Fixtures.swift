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

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranskribeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
