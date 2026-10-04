import Foundation

/// Where a recorded track came from. Imported files have no source.
public enum TrackSource: String, Codable, Sendable {
    case microphone
    case system
}

/// Speaker numbering: the microphone in a Mic + System recording is always `me`;
/// voices found by speaker detection are numbered from 1.
public enum SpeakerID {
    public static let me = 0
    /// Other people heard on the microphone of a Mic + System recording (someone in the room
    /// with you) are numbered from here, so they never collide with voices from the call.
    public static let firstInRoom = 100

    public static func isOnMicrophone(_ speaker: Int?) -> Bool {
        speaker.map { $0 == me || $0 >= firstInRoom } ?? false
    }
}

public struct Word: Codable, Equatable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct Segment: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speaker: Int?
    public var words: [Word]

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String, speaker: Int? = nil, words: [Word] = []) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.words = words
    }

    private enum CodingKeys: String, CodingKey { case id, start, end, text, speaker, words }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        text = try container.decode(String.self, forKey: .text)
        words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
        if let number = try? container.decodeIfPresent(Int.self, forKey: .speaker) {
            speaker = number
        } else {
            // Version 1 stored "me" / "others".
            let legacy = try? container.decodeIfPresent(String.self, forKey: .speaker)
            speaker = legacy.map { $0 == "me" ? SpeakerID.me : 1 }
        }
    }
}

/// One audio file belonging to a transcript. `offset` is where the track starts
/// relative to the beginning of the transcript timeline.
public struct AudioTrack: Codable, Equatable, Hashable, Sendable {
    public var fileName: String
    public var source: TrackSource?
    public var offset: TimeInterval

    public init(fileName: String, source: TrackSource? = nil, offset: TimeInterval = 0) {
        self.fileName = fileName
        self.source = source
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey { case fileName, source, offset, speaker }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        offset = try container.decodeIfPresent(TimeInterval.self, forKey: .offset) ?? 0
        if let source = try container.decodeIfPresent(TrackSource.self, forKey: .source) {
            self.source = source
        } else {
            let legacy = try container.decodeIfPresent(String.self, forKey: .speaker)
            source = legacy.map { $0 == "me" ? .microphone : .system }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encode(offset, forKey: .offset)
    }
}

public enum TranscriptStatus: Codable, Equatable, Hashable, Sendable {
    case pending
    case transcribing
    case done
    case failed(String)
}

public struct Transcript: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var language: String?
    public var tracks: [AudioTrack]
    public var segments: [Segment]
    public var status: TranscriptStatus
    /// Names the user gave to speakers. Unnamed speakers get a default name.
    public var speakerNames: [Int: String]
    /// Which speaker is the user ("me"), shown on the right like a sent message.
    public var meSpeaker: Int?
    public var summary: AISummary?
    public var chat: AIChat?
    /// The quality setting the current text was produced with (nil = before qualities existed).
    public var quality: TranscriptionQuality?
    /// Speakers linked to people the user knows.
    public var speakerPeople: [Int: UUID] = [:]
    /// Recordings that continue the same conversation share a thread.
    public var threadID: UUID?
    /// Each speaker's voiceprint, to recognize them in other recordings.
    public var speakerVoiceprints: [Int: [Float]] = [:]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        language: String? = nil,
        tracks: [AudioTrack],
        segments: [Segment] = [],
        status: TranscriptStatus = .pending,
        speakerNames: [Int: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.language = language
        self.tracks = tracks
        self.segments = segments
        self.status = status
        self.speakerNames = speakerNames
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, duration, language, tracks, segments, status, speakerNames, meSpeaker, summary, chat, quality, speakerPeople, threadID
        case speakerVoiceprints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        tracks = try container.decode([AudioTrack].self, forKey: .tracks)
        segments = try container.decode([Segment].self, forKey: .segments)
        status = try container.decode(TranscriptStatus.self, forKey: .status)
        speakerNames = try container.decodeIfPresent([Int: String].self, forKey: .speakerNames) ?? [:]
        meSpeaker = try container.decodeIfPresent(Int.self, forKey: .meSpeaker)
        summary = try container.decodeIfPresent(AISummary.self, forKey: .summary)
        chat = try container.decodeIfPresent(AIChat.self, forKey: .chat)
        quality = try container.decodeIfPresent(TranscriptionQuality.self, forKey: .quality)
        speakerPeople = try container.decodeIfPresent([Int: UUID].self, forKey: .speakerPeople) ?? [:]
        threadID = try container.decodeIfPresent(UUID.self, forKey: .threadID)
        speakerVoiceprints = try container.decodeIfPresent([Int: [Float]].self, forKey: .speakerVoiceprints) ?? [:]
    }

    /// The user's own speaker: their explicit choice, or the microphone track of a Mic + System recording.
    public var resolvedMeSpeaker: Int? {
        meSpeaker ?? (tracks.contains { $0.source == .microphone } && speakers.contains(SpeakerID.me) ? SpeakerID.me : nil)
    }

    /// Speakers in order of first appearance.
    public var speakers: [Int] {
        var seen = Set<Int>()
        return segments.compactMap(\.speaker).filter { seen.insert($0).inserted }
    }

    /// Labels are only worth showing when more than one voice was found.
    public var hasSpeakers: Bool {
        speakers.count > 1
    }

    /// A linked person's name wins over a typed label.
    public func name(of speaker: Int, people: [Person]) -> String {
        if let id = speakerPeople[speaker], let person = people.first(where: { $0.id == id }) { return person.name }
        return name(of: speaker)
    }

    public func name(of speaker: Int) -> String {
        if let name = speakerNames[speaker], !name.isEmpty { return name }
        if speaker == meSpeaker || speaker == SpeakerID.me { return "Me" }
        // Count people, not internal numbers: "Speaker 2" is the second voice that appears.
        let others = speakers.filter { $0 != SpeakerID.me }
        return "Speaker \((others.firstIndex(of: speaker) ?? others.count) + 1)"
    }

    public var preview: String {
        segments.lazy.map { $0.text.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }
}
