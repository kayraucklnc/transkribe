import Foundation
import Testing
@testable import TranskribeCore

@Suite struct PeopleTests {
    private func transcript(_ title: String, at seconds: Double, people: [Int: UUID] = [:], thread: UUID? = nil) -> Transcript {
        var transcript = Fixtures.transcript(title: title, segments: [
            Segment(start: 0, end: 1, text: "Merhaba", speaker: 1),
            Segment(start: 1, end: 2, text: "Selam", speaker: 2),
        ])
        transcript.createdAt = Date(timeIntervalSince1970: seconds)
        transcript.speakerPeople = people
        transcript.threadID = thread
        return transcript
    }

    @Test func peopleStoreRoundTrips() throws {
        let store = PeopleStore(url: try Fixtures.temporaryDirectory().appendingPathComponent("people.json"))
        let hakan = Person(name: "Hakan Yılmaz", emails: ["hakan@example.com"])
        try store.save([hakan])
        #expect(try store.load() == [hakan])
    }

    @Test func linkedSpeakersShowThePersonsName() {
        let hakan = Person(name: "Hakan")
        var transcript = transcript("Call", at: 0, people: [1: hakan.id])
        transcript.speakerNames = [:]
        #expect(transcript.name(of: 1, people: [hakan]) == "Hakan")
        #expect(transcript.name(of: 2, people: [hakan]) == "Speaker 2")
    }

    @Test func conversationsWithAPersonNewestFirst() {
        let hakan = Person(name: "Hakan")
        let all = [
            transcript("First", at: 10, people: [1: hakan.id]),
            transcript("Other", at: 20),
            transcript("Second", at: 30, people: [2: hakan.id]),
        ]
        #expect(Conversations.with(hakan.id, in: all).map(\.title) == ["Second", "First"])
    }

    @Test func threadSessionsAreChronological() {
        let thread = UUID()
        let all = [transcript("B", at: 30, thread: thread), transcript("A", at: 10, thread: thread), transcript("X", at: 20)]
        #expect(Conversations.sessions(in: thread, from: all).map(\.title) == ["A", "B"])
    }

    @Test func groupChatsHaveMoreThanTwoPeople() {
        let a = Person(name: "A"), b = Person(name: "B")
        var group = transcript("Group", at: 0, people: [1: a.id, 2: b.id])
        group.segments.append(Segment(start: 2, end: 3, text: "Hi", speaker: 3))
        #expect(Conversations.isGroup(group))
        #expect(!Conversations.isGroup(transcript("Pair", at: 0)))
    }

    @Test func legacyTranscriptsDecodeWithoutPeopleOrThreads() throws {
        let store = TranscriptStore(rootDirectory: try Fixtures.temporaryDirectory())
        try store.save(Fixtures.transcript())
        let loaded = try store.loadAll().first
        #expect(loaded?.speakerPeople.isEmpty == true)
        #expect(loaded?.threadID == nil)
    }
}
