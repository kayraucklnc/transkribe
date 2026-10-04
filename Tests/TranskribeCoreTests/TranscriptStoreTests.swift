import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TranscriptStoreTests {
    @Test func savesAndLoadsRoundTrip() throws {
        let root = try Fixtures.temporaryDirectory()
        let store = TranscriptStore(rootDirectory: root)
        let transcript = Fixtures.transcript()

        try store.save(transcript)
        let loaded = try store.loadAll()

        #expect(loaded == [transcript])
    }

    @Test func loadAllSortsNewestFirst() throws {
        let store = TranscriptStore(rootDirectory: try Fixtures.temporaryDirectory())
        var older = Fixtures.transcript(title: "Old")
        older.createdAt = Date(timeIntervalSince1970: 1)
        var newer = Fixtures.transcript(title: "New")
        newer.createdAt = Date(timeIntervalSince1970: 2)

        try store.save(older)
        try store.save(newer)

        #expect(try store.loadAll().map(\.title) == ["New", "Old"])
    }

    @Test func interruptedTranscriptionsLoadAsPending() throws {
        let store = TranscriptStore(rootDirectory: try Fixtures.temporaryDirectory())
        var transcript = Fixtures.transcript()
        transcript.status = .transcribing
        try store.save(transcript)

        #expect(try store.loadAll().first?.status == .pending)
    }

    @Test func skipsCorruptEntries() throws {
        let root = try Fixtures.temporaryDirectory()
        let store = TranscriptStore(rootDirectory: root)
        try store.save(Fixtures.transcript())
        let junk = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: junk.appendingPathComponent("transcript.json"))

        #expect(try store.loadAll().count == 1)
    }

    @Test func deleteRemovesFolderAndAudio() throws {
        let store = TranscriptStore(rootDirectory: try Fixtures.temporaryDirectory())
        let transcript = Fixtures.transcript()
        try store.save(transcript)
        let audio = store.audioURL(for: transcript, track: transcript.tracks[0])
        try Data([1, 2, 3]).write(to: audio)

        try store.delete(transcript)

        #expect(try store.loadAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }

    @Test func recoversInterruptedRecordings() throws {
        let root = try Fixtures.temporaryDirectory()
        let store = TranscriptStore(rootDirectory: root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appendingPathComponent(RecordingSession.microphoneFile))
        try Data([1]).write(to: folder.appendingPathComponent(RecordingSession.systemFile))

        let recovered = try store.recoverInterruptedRecordings()

        #expect(recovered.count == 1)
        #expect(recovered[0].status == .pending)
        #expect(Set(recovered[0].tracks.compactMap(\.source)) == [.microphone, .system])
        #expect(try store.loadAll().map(\.id) == recovered.map(\.id))
    }

    @Test func ignoresEmptyOrphanFolders() throws {
        let root = try Fixtures.temporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(UUID().uuidString), withIntermediateDirectories: true)
        #expect(try TranscriptStore(rootDirectory: root).recoverInterruptedRecordings().isEmpty)
    }

    @Test func emptyRootLoadsNothing() throws {
        let root = try Fixtures.temporaryDirectory().appendingPathComponent("missing")
        #expect(try TranscriptStore(rootDirectory: root).loadAll().isEmpty)
    }
}

@Suite struct CheckpointTests {
    @Test func savesLoadsAndClearsTrackCheckpoints() throws {
        let store = TranscriptStore(rootDirectory: try Fixtures.temporaryDirectory())
        let transcript = Fixtures.transcript()
        try store.save(transcript)
        let checkpoint = TrackCheckpoint(committedUntil: 42, segments: [
            RawSegment(start: 0, end: 4, text: "Merhaba", words: [Word(start: 0, end: 1, text: " Merhaba")]),
        ], language: "tr")

        try store.saveCheckpoint(checkpoint, for: transcript, track: transcript.tracks[0])
        #expect(store.loadCheckpoint(for: transcript, track: transcript.tracks[0]) == checkpoint)

        store.clearCheckpoints(for: transcript)
        #expect(store.loadCheckpoint(for: transcript, track: transcript.tracks[0]) == nil)
    }

    @Test func meSpeakerRoundTripsAndDefaultsToNil() throws {
        let store = TranscriptStore(rootDirectory: try Fixtures.temporaryDirectory())
        var transcript = Fixtures.transcript()
        #expect(transcript.meSpeaker == nil)
        transcript.meSpeaker = 2
        try store.save(transcript)
        #expect(try store.loadAll().first?.meSpeaker == 2)
    }
}
