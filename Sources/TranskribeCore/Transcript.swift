import Foundation

/// Who is speaking in a segment. Only set when a recording captured the microphone
/// and system audio as separate tracks.
public enum Speaker: String, Codable, Sendable {
    case me
    case others

    public var label: String {
        switch self {
        case .me: "Me"
        case .others: "Others"
        }
    }
}

public struct Segment: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speaker: Speaker?

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String, speaker: Speaker? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

/// One audio file belonging to a transcript. `offset` is where the track starts
/// relative to the beginning of the transcript timeline.
public struct AudioTrack: Codable, Equatable, Hashable, Sendable {
    public var fileName: String
    public var speaker: Speaker?
    public var offset: TimeInterval

    public init(fileName: String, speaker: Speaker? = nil, offset: TimeInterval = 0) {
        self.fileName = fileName
        self.speaker = speaker
        self.offset = offset
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

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        language: String? = nil,
        tracks: [AudioTrack],
        segments: [Segment] = [],
        status: TranscriptStatus = .pending
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.language = language
        self.tracks = tracks
        self.segments = segments
        self.status = status
    }

    public var hasSpeakers: Bool {
        segments.contains { $0.speaker != nil }
    }

    public var preview: String {
        segments.lazy.map { $0.text.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }
}
