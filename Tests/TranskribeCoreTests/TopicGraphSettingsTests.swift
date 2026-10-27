import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphSettingsTests {
    @Test(arguments: ["{}", #"{"namingRefreshWords":null,"futureFlag":true}"#,
                      #"{"decisionModelID":null,"namingModelID":null}"#])
    func missingRefreshWordsDecodeToSixty(_ json: String) throws {
        let settings = try JSONDecoder().decode(TopicGraphSettings.self, from: Data(json.utf8))
        #expect(settings == .default)
        #expect(settings.namingRefreshWords == 60)
    }

    @Test func preservesACustomRefreshThreshold() throws {
        let settings = TopicGraphSettings(namingRefreshWords: 25)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(TopicGraphSettings.self, from: data) == settings)
    }
}
