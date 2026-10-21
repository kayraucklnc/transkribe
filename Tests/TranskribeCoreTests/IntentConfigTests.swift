import Foundation
import Testing
@testable import TranskribeCore

@Suite struct IntentConfigTests {
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
