import Foundation

/// Someone the user talks with, optionally tied to a Contacts card.
public struct Person: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var emails: [String]
    /// `CNContact.identifier` when linked to the user's Contacts.
    public var contactIdentifier: String?
    /// What their voice sounds like, learned from conversations they were linked in.
    public var voiceprint: [Float]?
    /// How many recordings `voiceprint` was learned from.
    public var voiceSamples: Int?

    public init(id: UUID = UUID(), name: String, emails: [String] = [], contactIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.emails = emails
        self.contactIdentifier = contactIdentifier
    }

    public var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// People live in one small JSON file next to the library.
public struct PeopleStore: Sendable {
    public let url: URL

    public init(url: URL = TranscriptStore.defaultRoot.deletingLastPathComponent().appendingPathComponent("people.json")) {
        self.url = url
    }

    public func load() throws -> [Person] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Person].self, from: Data(contentsOf: url))
    }

    public func save(_ people: [Person]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(people).write(to: url, options: .atomic)
    }
}

/// Questions about how conversations relate: who was in them, which belong together.
public enum Conversations {
    public static func with(_ person: Person.ID, in transcripts: [Transcript]) -> [Transcript] {
        transcripts.filter { $0.speakerPeople.values.contains(person) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// The recordings of one ongoing conversation, oldest first.
    public static func sessions(in thread: UUID, from transcripts: [Transcript]) -> [Transcript] {
        transcripts.filter { $0.threadID == thread }.sorted { $0.createdAt < $1.createdAt }
    }

    /// More than two voices: a group conversation rather than a one-to-one.
    public static func isGroup(_ transcript: Transcript) -> Bool {
        transcript.speakers.count > 2
    }
}
