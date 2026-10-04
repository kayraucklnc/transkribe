import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TitleGeneratorTests {
    @Test func usesFileNameWithoutExtension() {
        #expect(TitleGenerator.title(forFile: URL(fileURLWithPath: "/tmp/Team call.m4a")) == "Team call")
    }

    @Test func fallsBackForEmptyNames() {
        #expect(TitleGenerator.title(forFile: URL(fileURLWithPath: "/tmp/.m4a")) == "Untitled")
    }

    @Test func recordingTitleIncludesDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let title = TitleGenerator.recordingTitle(at: date, locale: Locale(identifier: "en_US"), timeZone: calendar.timeZone)
        #expect(title.hasPrefix("Recording · Nov 14, 2023"))
    }

    @Test func suggestsTitleFromFirstWords() {
        let segments = [Segment(start: 0, end: 1, text: " Okay so today we are going to talk about the roadmap for next quarter.")]
        #expect(TitleGenerator.suggestedTitle(from: segments) == "Okay so today we are going…")
        #expect(TitleGenerator.suggestedTitle(from: []) == nil)
    }
}

@Suite struct RecordingModelTests {
    @Test func sourcesMapToInputs() {
        #expect(RecordingSource.microphone.usesMicrophone && !RecordingSource.microphone.usesSystemAudio)
        #expect(!RecordingSource.system.usesMicrophone && RecordingSource.system.usesSystemAudio)
        #expect(RecordingSource.both.usesMicrophone && RecordingSource.both.usesSystemAudio)
    }

    @Test func permissionErrorsLinkToSettings() {
        #expect(RecordingError.microphonePermissionDenied.settingsURL != nil)
        #expect(RecordingError.systemAudioPermissionDenied.settingsURL != nil)
        #expect(RecordingError.nothingRecorded.settingsURL == nil)
        #expect(RecordingError.nothingRecorded.errorDescription?.isEmpty == false)
    }
}
