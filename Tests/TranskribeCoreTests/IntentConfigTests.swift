import Foundation
import Testing
@testable import TranskribeCore

@Suite struct IntentConfigTests {
    @Test func saveLoadRoundTripPreservesEveryField() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        let config = try JSONDecoder().decode(IntentConfig.self, from: Data(Self.validJSON.utf8))
        try config.save(to: url)
        let result = IntentConfig.load(from: url)
        #expect(result.error == nil)
        #expect(result.config == config)
    }

    @Test func atomicSaveReplacesTheFileWithoutChangingAnOpenReader() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        try IntentConfig().save(to: url)
        let previousBytes = try Data(contentsOf: url)
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        let replacement = try JSONDecoder().decode(IntentConfig.self, from: Data(Self.validJSON.utf8))
        try replacement.save(to: url)
        #expect(try reader.readToEnd() == previousBytes)
        #expect(IntentConfig.load(from: url).config == replacement)
    }

    @Test func validationRejectsAnInvalidSaveAndPreservesTheExistingFile() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        try Data("hand-edited invalid JSON".utf8).write(to: url)
        let invalid = try JSONDecoder().decode(IntentConfig.self,
            from: Data(Self.validJSON.replacingOccurrences(of: "explicit_ask", with: "none").utf8))
        let expected = AIError("Each intent must have a unique ID. The ID cannot be empty or none.")
        #expect(throws: expected) { try invalid.validate() }
        #expect(throws: expected) { try invalid.save(to: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "hand-edited invalid JSON")
    }

    @Test func saveCreatesTheSupportDirectoryOnFirstUse() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("Transkribe/intents.json")
        try IntentConfig().save(to: url)
        let result = IntentConfig.load(from: url)
        #expect(result.error == nil)
        #expect(result.config.intents.isEmpty)
    }

    @Test func enabledDefaultsToTrueForExistingFilesAndFalseSurvivesASave() throws {
        let legacy = try JSONDecoder().decode(IntentConfig.self, from: Data(Self.validJSON.utf8))
        #expect(legacy.intents.first?.enabled == true)
        let json = Self.validJSON.replacingOccurrences(of: "\"id\":", with: "\"enabled\":false,\"id\":")
        let disabled = try JSONDecoder().decode(IntentConfig.self, from: Data(json.utf8))
        #expect(disabled.intents.first?.enabled == false)
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        try disabled.save(to: url)
        #expect(IntentConfig.load(from: url).config.intents.first?.enabled == false)
    }

    @Test func bundledExamplesMatchTheDocumentedConfiguration() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let documented = IntentConfig.load(from: root.appendingPathComponent("docs/intents.example.json"))
        #expect(documented.error == nil)
        let bundled = try IntentConfig.examples()
        #expect(bundled == documented.config)
        #expect(bundled.intents.map(\.id) == ["explicit_ask", "competitor_question"])
    }

    @Test func loadsVersionOneFile() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        try Data(Self.validJSON.utf8).write(to: url)
        let result = IntentConfig.load(from: url)
        #expect(result.error == nil)
        let intent = try #require(result.config.intents.first)
        #expect(result.config.version == 1)
        #expect(intent.id == "explicit_ask")
        #expect(intent.description == "Grok was asked to do something")
        #expect(intent.examples == ["Grok, check Otter"])
        #expect(intent.speakers == .me)
        #expect(intent.action.destination == .webhook)
        #expect(intent.action.instruction == "Research the request.")
        #expect(intent.minConfidence == 0.8)
        #expect(intent.cooldownSec == 30)
    }

    @Test func missingFileDisablesIntentsWithAnError() throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        let result = IntentConfig.load(from: url)
        #expect(result.config.intents.isEmpty)
        #expect(result.error?.isEmpty == false)
    }

    @Test(arguments: [
        "not JSON", "{}",
        validJSON.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
        validJSON.replacingOccurrences(of: "explicit_ask", with: "none"),
        validJSON.replacingOccurrences(of: "explicit_ask", with: " "),
        validJSON.replacingOccurrences(of: "0.8", with: "1.1"),
        validJSON.replacingOccurrences(of: "0.8", with: "-0.1"),
        validJSON.replacingOccurrences(of: "30", with: "-1"),
        validJSON.replacingOccurrences(of: "\"me\"", with: "\"others\""),
        validJSON.replacingOccurrences(of: "webhook", with: "shell"),
        validJSON.replacingOccurrences(of: "Research the request.", with: " "),
    ])
    func invalidFileDisablesAllIntents(_ json: String) throws {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        try Data(json.utf8).write(to: url)
        let result = IntentConfig.load(from: url)
        #expect(result.config.intents.isEmpty)
        #expect(result.error?.isEmpty == false)
    }

    @Test func duplicateLabelsDisableAllIntents() throws {
        let object = try JSONSerialization.jsonObject(with: Data(Self.validJSON.utf8)) as! [String: Any]
        let intents = object["intents"] as! [Any]
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "intents": intents + intents])
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("intents.json")
        try data.write(to: url)
        let result = IntentConfig.load(from: url)
        #expect(result.config.intents.isEmpty)
        #expect(result.error?.isEmpty == false)
    }

    static let validJSON = #"{"version":1,"intents":[{"id":"explicit_ask","description":"Grok was asked to do something","examples":["Grok, check Otter"],"speakers":"me","action":{"destination":"webhook","instruction":"Research the request."},"minConfidence":0.8,"cooldownSec":30}]}"#
}
