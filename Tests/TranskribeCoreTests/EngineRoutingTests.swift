import Foundation
import Testing
@testable import TranskribeCore

@Suite struct EngineRoutingTests {
    @Test func instantUsesTheMacWhenItKnowsEveryLanguage() {
        #expect(EngineCatalog.setup(for: .instant, languages: ["en", "it"], appleAvailable: true) == .apple)
    }

    @Test func instantFallsBackToWhisperForTurkish() {
        // The Mac's recognizer has no Turkish: it would hear a Turkish call as English.
        #expect(EngineCatalog.setup(for: .instant, languages: ["en", "tr"], appleAvailable: true)
            == .whisper(model: EngineCatalog.turboModel, european: true))
        #expect(EngineCatalog.setup(for: .instant, languages: ["en"], appleAvailable: false)
            == .whisper(model: EngineCatalog.turboModel, european: true))
    }

    @Test func theEuropeanModelIsOnlyAddedForItsLanguages() {
        #expect(EngineCatalog.setup(for: .balanced, languages: ["tr"], appleAvailable: true)
            == .whisper(model: EngineCatalog.turboModel, european: false))
    }

    @Test(arguments: [TranscriptionQuality.instant, .balanced, .best])
    func retiredModelsAreNeverChosen(_ quality: TranscriptionQuality) {
        #expect(!EngineCatalog.retiredModels.contains(EngineCatalog.whisperModel(for: quality)))
    }

    @Test func downloadSizeFollowsTheChosenModel() {
        #expect(EngineCatalog.downloadSize(for: .instant, languages: ["en"]) == 0)
        #expect(EngineCatalog.downloadSize(for: .balanced, languages: ["tr"]) == 650)
        #expect(EngineCatalog.downloadSize(for: .instant, languages: ["tr"]) == 650)
    }

    @Test func retiredModelsAreDeletedFromTheModelsFolderOnly() throws {
        let models = try Fixtures.temporaryDirectory()
        let retired = models.appendingPathComponent("models/argmaxinc/whisperkit-coreml/old-model")
        let kept = models.appendingPathComponent("models/argmaxinc/whisperkit-coreml/new-model")
        for folder in [retired, kept] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 100).write(to: folder.appendingPathComponent("weight.bin"))
        }
        // A marker pointing outside the Models folder must never be followed.
        let outside = try Fixtures.temporaryDirectory().appendingPathComponent("old-model")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try outside.path.write(to: models.appendingPathComponent("old-model.ready"), atomically: true, encoding: .utf8)

        let freed = ModelFiles.removeRetired(["old-model"], in: models)
        #expect(freed == 100)
        #expect(!FileManager.default.fileExists(atPath: retired.path))
        #expect(!FileManager.default.fileExists(atPath: models.appendingPathComponent("old-model.ready").path))
        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}
