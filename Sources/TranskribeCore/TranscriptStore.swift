import Foundation

/// Persists each transcript in its own folder: `<root>/<id>/transcript.json` plus its audio tracks.
public struct TranscriptStore: Sendable {
    public let rootDirectory: URL
    private static let fileName = "transcript.json"

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public static var defaultRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Transkribe/Library", isDirectory: true)
    }

    public func directory(for transcript: Transcript) -> URL {
        rootDirectory.appendingPathComponent(transcript.id.uuidString, isDirectory: true)
    }

    public func audioURL(for transcript: Transcript, track: AudioTrack) -> URL {
        directory(for: transcript).appendingPathComponent(track.fileName)
    }

    /// Creates the transcript's folder and returns it so callers can write audio into it.
    @discardableResult
    public func prepareDirectory(for transcript: Transcript) throws -> URL {
        let directory = directory(for: transcript)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func save(_ transcript: Transcript) throws {
        let directory = try prepareDirectory(for: transcript)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(transcript).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// Loads every readable transcript, newest first. Unreadable folders are skipped.
    /// Anything that was mid-transcription when the app quit comes back as `.pending`.
    public func loadAll() throws -> [Transcript] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootDirectory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try fm.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
            .compactMap { folder -> Transcript? in
                let file = folder.appendingPathComponent(Self.fileName)
                guard let data = try? Data(contentsOf: file),
                      var transcript = try? decoder.decode(Transcript.self, from: data) else { return nil }
                if transcript.status == .transcribing { transcript.status = .pending }
                return transcript
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Recordings interrupted by a quit or crash leave audio without a `transcript.json`.
    /// Turns those folders back into pending transcripts so nothing is lost.
    public func recoverInterruptedRecordings() throws -> [Transcript] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootDirectory.path) else { return [] }
        let candidates: [(file: String, speaker: Speaker)] = [
            (RecordingSession.microphoneFile, .me),
            (RecordingSession.systemFile, .others),
        ]
        var recovered: [Transcript] = []
        for folder in try fm.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: [.creationDateKey]) {
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  !fm.fileExists(atPath: folder.appendingPathComponent(Self.fileName).path) else { continue }
            let tracks = candidates
                .filter { fm.fileExists(atPath: folder.appendingPathComponent($0.file).path) }
                .map { AudioTrack(fileName: $0.file, speaker: $0.speaker) }
            guard !tracks.isEmpty else { continue }
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let transcript = Transcript(id: id, title: TitleGenerator.recordingTitle(at: created), createdAt: created, tracks: tracks)
            try save(transcript)
            recovered.append(transcript)
        }
        return recovered
    }

    public func delete(_ transcript: Transcript) throws {
        let directory = directory(for: transcript)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
