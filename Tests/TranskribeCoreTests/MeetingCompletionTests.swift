import Foundation
import Testing
@testable import TranskribeCore

@Suite struct MeetingCompletionTests {
    @Test @MainActor func endNotificationReadsTheLastCommittedLiveBatch() async {
        var transcript = Transcript(title: "Live", tracks: [],
            segments: [.init(start: 0, end: 1, text: "First batch")], status: .transcribing)
        let live = MCPLiveTools(snapshots: { [.init(transcript: transcript, isLive: true)] })
        let server = MCPServer(library: { ConversationLibrary(transcripts: [], people: []) }, extraTools: live.tools)
        let transcription = Task<Void, Error> { @MainActor in
            await Task.yield()
            transcript.segments.append(.init(start: 1, end: 2, text: "Last committed batch"))
            transcript.status = .done
        }
        var notificationRead: MCPToolResult?
        await MeetingCompletion.finish(transcription: transcription, recover: { _ in
            Issue.record("The live transcription unexpectedly failed.")
        }, sendEnded: {
            notificationRead = server.call("read_conversation", arguments: ["id": transcript.id.uuidString])
        })
        #expect(notificationRead?.isError == false)
        #expect(notificationRead?.text.contains("First batch") == true)
        #expect(notificationRead?.text.contains("Last committed batch") == true)
    }

    @Test(arguments: [false, true]) @MainActor
    func failureRecoveryPrecedesTheEndNotification(cancelled: Bool) async {
        let transcription = Task<Void, Error> { @MainActor in
            try Task.checkCancellation()
            throw AIError("The live transcription failed.")
        }
        if cancelled { transcription.cancel() }
        var recovered = false
        var notifications = 0
        await MeetingCompletion.finish(transcription: transcription, recover: { error in
            #expect(cancelled ? error is CancellationError : error is AIError)
            recovered = true
        }, sendEnded: {
            #expect(recovered)
            notifications += 1
        })
        #expect(notifications == 1)
    }

    @Test @MainActor func abandonCancelsAndFinalizesWithoutWaitingForTheTranscription() async {
        let gate = TranscriptionGate()
        let transcription = Task<Void, Error> { @MainActor in
            await withCheckedContinuation { gate.continuation = $0 }
        }
        while gate.continuation == nil { await Task.yield() }
        var finalized = 0
        await MeetingCompletion.abandon(transcription: transcription, finalize: { finalized += 1 })
        #expect(finalized == 1)
        #expect(transcription.isCancelled)
        gate.continuation?.resume()
        _ = await transcription.result
    }
}

@MainActor private final class TranscriptionGate {
    var continuation: CheckedContinuation<Void, Never>?
}
