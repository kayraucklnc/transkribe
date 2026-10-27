import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphSettingsTests {
    @Test(arguments: ["{}", #"{"namingRefreshWords":null,"futureFlag":true}"#])
    func missingRefreshWordsDecodeToSixty(_ json: String) throws {
        let settings = try JSONDecoder().decode(TopicGraphSettings.self, from: Data(json.utf8))
        #expect(settings == .default)
        #expect(settings.namingRefreshWords == 60)
    }
}
