import Foundation
import Testing
@testable import TranskribeCore

@Suite struct ModelFilesTests {
    private func makeModel(skipping missing: String? = nil) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
        for part in ModelFiles.requiredParts {
            let weights = folder.appendingPathComponent("\(part).mlmodelc/weights")
            try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
            try Data([1]).write(to: folder.appendingPathComponent("\(part).mlmodelc/coremldata.bin"))
            let weight = weights.appendingPathComponent("weight.bin")
            if weight.path.contains(missing ?? "\u{0}") { continue }
            try Data([1]).write(to: weight)
        }
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        return folder
    }

    @Test func completeModelPasses() throws {
        #expect(ModelFiles.isComplete(try makeModel()))
    }

    @Test func missingDecoderWeightsFail() throws {
        #expect(!ModelFiles.isComplete(try makeModel(skipping: "TextDecoder.mlmodelc/weights")))
    }

    @Test func emptyWeightFileFails() throws {
        let folder = try makeModel()
        try Data().write(to: folder.appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin"))
        #expect(!ModelFiles.isComplete(folder))
    }

    @Test func missingFolderFails() {
        #expect(!ModelFiles.isComplete(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")))
    }
}
