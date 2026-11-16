import Foundation

public struct EvaluationScheduler: Sendable {
    private let minNewWords: Int
    private let seconds: TimeInterval
    private var evaluatedWordCount = 0
    private var evaluatedAt: Date

    public init(minNewWords: Int = 20, seconds: TimeInterval = 10, now: Date = Date()) {
        self.minNewWords = max(1, minNewWords)
        self.seconds = seconds.isFinite && seconds > 0 ? seconds : 10
        self.evaluatedAt = now
    }

    /// Pass the cumulative count of committed words. Exclude pending words.
    public mutating func shouldEvaluate(committedWordCount: Int, at now: Date = Date()) -> Bool {
        guard committedWordCount - evaluatedWordCount >= minNewWords
                || now.timeIntervalSince(evaluatedAt) >= seconds else { return false }
        didEvaluate(committedWordCount: committedWordCount, at: now)
        return true
    }

    /// Records batches consumed by a forced pass or while a previous request was running.
    public mutating func didEvaluate(committedWordCount: Int, at now: Date = Date()) {
        evaluatedWordCount = committedWordCount
        evaluatedAt = now
    }
}
