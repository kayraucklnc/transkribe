import Foundation
import Testing
@testable import TranskribeCore

@Suite struct EvaluationSchedulerTests {
    let start = Date(timeIntervalSince1970: 0)

    @Test func forcedOrQueuedEvaluationResetsTheConsumedWordCount() {
        var scheduler = EvaluationScheduler(minNewWords: 5, seconds: 10, now: start)
        scheduler.didEvaluate(committedWordCount: 2, at: start.addingTimeInterval(1))
        let before = scheduler.shouldEvaluate(committedWordCount: 6, at: start.addingTimeInterval(2))
        let threshold = scheduler.shouldEvaluate(committedWordCount: 7, at: start.addingTimeInterval(2))
        #expect(!before)
        #expect(threshold)
        scheduler.didEvaluate(committedWordCount: 15, at: start.addingTimeInterval(3))
        let afterQueued = scheduler.shouldEvaluate(committedWordCount: 16, at: start.addingTimeInterval(4))
        let timer = scheduler.shouldEvaluate(committedWordCount: 16, at: start.addingTimeInterval(13))
        #expect(!afterQueued)
        #expect(timer)
    }

    @Test func evaluatesAtNewCommittedWordThreshold() {
        var scheduler = EvaluationScheduler(minNewWords: 5, seconds: 10, now: start)
        let before = scheduler.shouldEvaluate(committedWordCount: 4, at: start)
        let threshold = scheduler.shouldEvaluate(committedWordCount: 5, at: start)
        let beforeNext = scheduler.shouldEvaluate(committedWordCount: 9, at: start)
        let next = scheduler.shouldEvaluate(committedWordCount: 10, at: start)
        #expect(!before)
        #expect(threshold)
        #expect(!beforeNext)
        #expect(next)
    }

    @Test func timerEvaluatesBelowTheWordThresholdAndResetsBothThresholds() {
        var scheduler = EvaluationScheduler(minNewWords: 5, seconds: 10, now: start)
        let before = scheduler.shouldEvaluate(committedWordCount: 3, at: start.addingTimeInterval(9))
        let timer = scheduler.shouldEvaluate(committedWordCount: 3, at: start.addingTimeInterval(10))
        let beforeWords = scheduler.shouldEvaluate(committedWordCount: 7, at: start.addingTimeInterval(11))
        let words = scheduler.shouldEvaluate(committedWordCount: 8, at: start.addingTimeInterval(12))
        let beforeTimer = scheduler.shouldEvaluate(committedWordCount: 8, at: start.addingTimeInterval(21))
        let nextTimer = scheduler.shouldEvaluate(committedWordCount: 8, at: start.addingTimeInterval(22))
        #expect(!before)
        #expect(timer)
        #expect(!beforeWords)
        #expect(words)
        #expect(!beforeTimer)
        #expect(nextTimer)
    }
}
