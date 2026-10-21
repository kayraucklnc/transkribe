import Foundation
import Testing
@testable import TranskribeCore

@Suite struct AnswerStoreTests {
    @Test func postAndUpdateReplaceAnswerText() throws {
        let transcript = Transcript(title: "Live", tracks: [], status: .transcribing)
        let store = AnswerStore(snapshots: { [.init(transcript: transcript, isLive: true)] })
        let answer = try store.post(conversationId: transcript.id, markdown: "First take")
        let updated = try store.update(answerId: answer.id, markdown: "Final answer", final: true)
        #expect(updated.markdown == "Final answer")
        #expect(updated.isFinal)
        #expect(store.answers(for: transcript.id) == [updated])
    }
    @Test func unknownConversationAndAnswerIDsAreRejected() {
        let store = AnswerStore(snapshots: { [] })
        #expect(throws: AnswerStoreError.unknownConversation) {
            try store.post(conversationId: UUID(), markdown: "Answer")
        }
        #expect(throws: AnswerStoreError.unknownAnswer) {
            try store.update(answerId: UUID(), markdown: "Answer", final: false)
        }
    }

    @Test func markdownCapUsesUTF8BytesForPostsAndUpdates() throws {
        let transcript = Transcript(title: "Live", tracks: [])
        let store = AnswerStore(snapshots: { [.init(transcript: transcript, isLive: true)] })
        let maximum = String(repeating: "é", count: 16_384)
        let answer = try store.post(conversationId: transcript.id, markdown: maximum)
        #expect(answer.markdown == maximum)
        #expect(throws: AnswerStoreError.tooLarge) {
            try store.post(conversationId: transcript.id, markdown: maximum + "a")
        }
        #expect(throws: AnswerStoreError.tooLarge) {
            try store.update(answerId: answer.id, markdown: maximum + "a", final: false)
        }
        #expect(store.answers(for: transcript.id) == [answer])
    }

    @Test func endedConversationsExpireAt24HoursForPostsAndUpdates() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var time = start
        let live = Transcript(title: "Long live meeting", createdAt: start.addingTimeInterval(-200_000), tracks: [])
        let ended = Transcript(title: "Ended", tracks: [])
        let noEnd = Transcript(title: "No end time", tracks: [])
        let store = AnswerStore(snapshots: {
            [.init(transcript: live, isLive: true),
             .init(transcript: ended, isLive: false, endedAt: start),
             .init(transcript: noEnd, isLive: false)]
        }, now: { time })
        let answer = try store.post(conversationId: ended.id, markdown: "First")
        time = start.addingTimeInterval(86_399)
        _ = try store.update(answerId: answer.id, markdown: "Recent", final: false)
        _ = try store.post(conversationId: ended.id, markdown: "Recent")
        time = start.addingTimeInterval(86_400)
        #expect(throws: AnswerStoreError.conversationExpired) {
            try store.post(conversationId: ended.id, markdown: "Too late")
        }
        #expect(throws: AnswerStoreError.conversationExpired) {
            try store.update(answerId: answer.id, markdown: "Too late", final: false)
        }
        #expect(throws: AnswerStoreError.conversationExpired) {
            try store.post(conversationId: noEnd.id, markdown: "Unknown end")
        }
        _ = try store.post(conversationId: live.id, markdown: "Still live")
    }

    @Test func finalAnswerRejectsAllLaterUpdates() throws {
        let transcript = Transcript(title: "Live", tracks: [])
        let store = AnswerStore(snapshots: { [.init(transcript: transcript, isLive: true)] })
        let answer = try store.post(conversationId: transcript.id, markdown: "First")
        let final = try store.update(answerId: answer.id, markdown: "Done", final: true)
        for finalFlag in [false, true] {
            #expect(throws: AnswerStoreError.alreadyFinal) {
                try store.update(answerId: answer.id, markdown: "Overwrite", final: finalFlag)
            }
        }
        #expect(store.answers(for: transcript.id) == [final])
    }

    @Test func rateLimitAllows30UpdatesPerRollingMinutePerAnswer() throws {
        var time = Date(timeIntervalSince1970: 1_000_000)
        let transcript = Transcript(title: "Live", tracks: [])
        let store = AnswerStore(snapshots: { [.init(transcript: transcript, isLive: true)] }, now: { time })
        let first = try store.post(conversationId: transcript.id, markdown: "First")
        let second = try store.post(conversationId: transcript.id, markdown: "Second")
        #expect(throws: AnswerStoreError.tooLarge) {
            try store.update(answerId: first.id, markdown: String(repeating: "x", count: 32_769), final: false)
        }
        for index in 1...30 {
            _ = try store.update(answerId: first.id, markdown: "Update \(index)", final: false)
        }
        time.addTimeInterval(59.999)
        #expect(throws: AnswerStoreError.rateLimited) {
            try store.update(answerId: first.id, markdown: "Blocked", final: true)
        }
        #expect(store.answers(for: transcript.id).first { $0.id == first.id }?.markdown == "Update 30")
        _ = try store.update(answerId: second.id, markdown: "Independent", final: false)
        time.addTimeInterval(0.001)
        let final = try store.update(answerId: first.id, markdown: "Allowed", final: true)
        #expect(final.isFinal)
    }

    @Test func snapshotProviderCanReadExistingAnswers() throws {
        let transcript = Transcript(title: "Live", tracks: [])
        weak var store: AnswerStore?
        let current = AnswerStore(snapshots: {
            _ = store?.answers(for: transcript.id)
            return [.init(transcript: transcript, isLive: true)]
        })
        store = current
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            if let answer = try? current.post(conversationId: transcript.id, markdown: "First") {
                _ = try? current.update(answerId: answer.id, markdown: "Updated", final: true)
            }
            completed.signal()
        }
        let result = completed.wait(timeout: .now() + 2)
        #expect(result == .success)
        if result == .success {
            #expect(current.answers(for: transcript.id).first?.markdown == "Updated")
        }
    }

}
