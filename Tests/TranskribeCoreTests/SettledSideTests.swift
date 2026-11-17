import Foundation
import Testing
@testable import TranskribeCore

@Suite struct SettledSideTests {
    private let callTracks = [AudioTrack(fileName: "microphone.m4a", source: .microphone),
                              AudioTrack(fileName: "system.m4a", source: .system)]

    private func transcript(speakers: [Int], tracks: [AudioTrack], status: TranscriptStatus) -> Transcript {
        var transcript = Fixtures.transcript(
            segments: speakers.enumerated().map { index, speaker in
                Segment(start: Double(index), end: Double(index) + 1, text: "Söyle.", speaker: speaker)
            },
            tracks: tracks
        )
        transcript.status = status
        return transcript
    }

    @Test(arguments: [TranscriptStatus.transcribing, .pending, .failed("stopped")])
    func callVoicesGoLeftWhileStillTranscribing(_ status: TranscriptStatus) {
        let call = transcript(speakers: [SpeakerID.me, 1, 2], tracks: callTracks, status: status)
        #expect(call.speakersWithSettledSide == [SpeakerID.me, 1, 2])
    }

    @Test func otherMicrophoneVoicesWaitInTheMiddle() {
        let call = transcript(speakers: [SpeakerID.me, 1, SpeakerID.firstInRoom], tracks: callTracks, status: .transcribing)
        #expect(call.speakersWithSettledSide == [SpeakerID.me, 1])
    }

    @Test func meIsSettledBeforeSpeakingInACall() {
        let call = transcript(speakers: [1], tracks: callTracks, status: .transcribing)
        #expect(call.speakersWithSettledSide == [SpeakerID.me, 1])
    }

    @Test func singleTrackRecordingsWaitUntilDone() {
        let tracks = [AudioTrack(fileName: "microphone.m4a", source: .microphone)]
        #expect(transcript(speakers: [0, 1], tracks: tracks, status: .transcribing).speakersWithSettledSide == [])
    }

    @Test func everythingIsSettledOnceDone() {
        #expect(transcript(speakers: [SpeakerID.me, 1, SpeakerID.firstInRoom], tracks: callTracks, status: .done)
            .speakersWithSettledSide == nil)
    }
}
