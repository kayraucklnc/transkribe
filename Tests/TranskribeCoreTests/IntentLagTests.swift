import Foundation
import Testing
@testable import TranskribeCore

@Suite struct IntentLagTests {
    @Test func recordsEachStageOnTheMeetingClock() throws {
        let began = Date(timeIntervalSince1970: 1_000)
        let record = IntentLagRecord(meetingID: UUID(), intentID: "competitor", from: 10, to: 14,
            meetingStartedAt: began, committedAt: began.addingTimeInterval(26),
            verdictAt: began.addingTimeInterval(28), actionSentAt: began.addingTimeInterval(28.5))
        #expect(record.speechEndedAt == Date(timeIntervalSince1970: 1_014))
        #expect(record.transcriptionLag == 12)
        #expect(record.decisionLag == 2)
        #expect(record.actionLag == 0.5)
        #expect(record.totalLag == 14.5)
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(IntentLagRecord.self, from: data) == record)
    }
}
