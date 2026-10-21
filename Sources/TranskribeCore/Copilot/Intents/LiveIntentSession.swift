import Foundation

public struct IntentDispatch: Sendable, Identifiable {
    public let id = UUID()
    public let meetingID: UUID
    public let match: IntentMatch
    public let context: [Segment]
    public let meetingStartedAt: Date
    public let committedAt: Date
    public let verdictAt: Date

    public var taskKey: String { "intent-\(meetingID)-\(id)" }

    public func lag(actionSentAt: Date) -> IntentLagRecord {
        IntentLagRecord(meetingID: meetingID, intentID: match.intent.id, from: match.from, to: match.to,
            meetingStartedAt: meetingStartedAt, committedAt: committedAt, verdictAt: verdictAt, actionSentAt: actionSentAt)
    }
}

/// Owns the committed speech and intent policy for one meeting.
public actor LiveIntentSession {
    private struct RangeKey: Hashable {
        let track: String
        let from: TimeInterval
        let to: TimeInterval
    }

    private let meetingID: UUID
    private let startedAt: Date
    private let engine: IntentEngine
    private var tracks: [String: [Segment]] = [:]
    private var committedAt: [RangeKey: Date] = [:]
    private var hasNewSpeech = false
    private var wordCount = 0
    private var scheduler: EvaluationScheduler
    private var evaluating = false
    private var mutedIntents = Set<String>()

    public init(meetingID: UUID, startedAt: Date, config: IntentConfig, provider: any AIProvider,
                model: AIModel, minNewWords: Int = 20) {
        self.meetingID = meetingID
        self.startedAt = startedAt
        self.scheduler = EvaluationScheduler(minNewWords: minNewWords, now: startedAt)
        self.engine = IntentEngine(config: config, provider: provider, model: model)
    }

    public func evaluate(enabled: Bool, meIsReliable: Bool, at now: Date = Date(), force: Bool = false) async throws -> IntentDispatch? {
        guard enabled, hasNewSpeech, !evaluating else { return nil }
        guard force || scheduler.shouldEvaluate(committedWordCount: wordCount, at: now) else { return nil }
        evaluating = true
        defer { evaluating = false }
        hasNewSpeech = false
        let all = tracks.values.flatMap { $0 }.sorted { $0.start < $1.start }
        let end = all.map(\.end).max() ?? 0
        let segments = all.filter { $0.end > end - 120 }
        let commitTimes = committedAt
        guard let match = try await engine.evaluate(meetingID: meetingID, committedSegments: segments,
                                                    meIsReliable: meIsReliable, at: now),
              !mutedIntents.contains(match.intent.id) else { return nil }
        let commit = commitTimes.filter { $0.key.from < match.to && $0.key.to > match.from }.values.max() ?? now
        return IntentDispatch(meetingID: meetingID, match: match, context: segments, meetingStartedAt: startedAt,
                              committedAt: commit, verdictAt: Date())
    }
    public func receive(track: String, committed: [Segment], at now: Date = Date()) {
        for segment in committed {
            let key = RangeKey(track: track, from: segment.start, to: segment.end)
            if committedAt[key] == nil {
                committedAt[key] = now
                hasNewSpeech = true
                wordCount += segment.text.split(whereSeparator: \.isWhitespace).count
            }
        }
        tracks[track] = committed
    }

    public func mute(_ intentID: String) async {
        mutedIntents.insert(intentID)
        await engine.mute(intentID, meetingID: meetingID)
    }

}
