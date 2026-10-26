import Foundation
import Testing
@testable import TranskribeCore

@Suite struct TopicGraphStoreTests {
    @Test func savesGraphBesideTranscriptWithoutPendingText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = Transcript(title: "Meeting", tracks: [])
        let transcripts = TranscriptStore(rootDirectory: root)
        try transcripts.save(transcript)
        let transcriptURL = transcripts.directory(for: transcript).appendingPathComponent("transcript.json")
        let transcriptData = try Data(contentsOf: transcriptURL)
        let store = TopicGraphStore(rootDirectory: root)
        var graph = TopicGraph(meetingId: transcript.id)
        try graph.apply(.init(route: .new, points: [.init(track: 0, start: 0, end: 2, text: "Committed")]))
        graph.draft = "Pending text must stay in memory"
        try store.save(graph)

        let file = transcripts.directory(for: transcript).appendingPathComponent("graph.json")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect(json["draft"] == nil)
        #expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains(graph.draft))
        let loaded = store.load(meetingId: transcript.id)
        #expect(loaded.error == nil)
        #expect(loaded.graph.draft.isEmpty)
        graph.draft = ""
        #expect(loaded.graph == graph)
        #expect(try Data(contentsOf: transcriptURL) == transcriptData)

        try graph.apply(.init(route: .new, points: [.init(track: 1, start: 5, end: 7, text: "Next")]))
        try store.save(graph)
        let replaced = store.load(meetingId: transcript.id)
        #expect(replaced.error == nil)
        #expect(replaced.graph == graph)
    }

    @Test func missingMalformedOrUnsupportedFilesReturnAnEmptyGraphAndAnError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TopicGraphStore(rootDirectory: root)
        let meetingId = UUID()
        let missing = store.load(meetingId: meetingId)
        #expect(missing.graph == TopicGraph(meetingId: meetingId))
        #expect(missing.error?.isEmpty == false)

        var graph = TopicGraph(meetingId: meetingId)
        try graph.apply(.init(route: .new, points: [.init(track: 0, start: 1, end: 3, text: "Topic")]))
        try store.save(graph)
        let file = store.fileURL(for: meetingId)
        let original = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var unsupported = original
        unsupported["version"] = 2
        var wrongMeeting = original
        wrongMeeting["meetingId"] = UUID().uuidString
        for data in [Data("{invalid".utf8), try JSONSerialization.data(withJSONObject: unsupported),
                     try JSONSerialization.data(withJSONObject: wrongMeeting)] {
            try data.write(to: file)
            let result = store.load(meetingId: meetingId)
            #expect(result.graph == TopicGraph(meetingId: meetingId))
            #expect(result.error?.isEmpty == false)
        }
    }

    @Test(arguments: ["current", "parent", "topicId", "pointId", "pointTopic", "pointRange", "pointTrack",
                      "duplicateRange", "stats", "edgeId", "edgePoint", "branchParent", "forwardReturn",
                      "confidence", "until", "name"])
    func invalidGraphInvariantsAlsoFailOnLoad(_ fault: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TopicGraphStore(rootDirectory: root)
        let meetingId = UUID()
        var graph = TopicGraph(meetingId: meetingId)
        let first = try #require(try graph.apply(.init(route: .new, points: [
            .init(track: 0, start: 1, end: 3, text: "First"),
        ])))
        let second = try #require(try graph.apply(.init(route: .new, points: [
            .init(track: 0, start: 4, end: 6, text: "Second"),
        ])))
        try graph.apply(.init(route: .side(second), points: [.init(track: 1, start: 4, end: 6, text: "Side")]))
        try graph.apply(.init(route: .merge(second), points: [.init(track: 1, start: 7, end: 8, text: "Merge")]))
        try graph.apply(.init(route: .returnTo(first), points: [.init(track: 0, start: 9, end: 10, text: "Return")]))
        try store.save(graph)
        #expect(store.load(meetingId: meetingId).graph == graph)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)) as? [String: Any])
        var topics = try #require(json["topics"] as? [[String: Any]])
        var points = try #require(json["points"] as? [[String: Any]])
        var edges = try #require(json["edges"] as? [[String: Any]])
        switch fault {
        case "current": json["currentTopicId"] = "missing"
        case "parent": topics[0]["parentId"] = topics[2]["id"]
        case "topicId": topics[1]["id"] = topics[0]["id"]
        case "pointId": points[1]["id"] = points[0]["id"]
        case "pointTopic": points[0]["topicId"] = "missing"
        case "pointRange": points[0]["end"] = 0
        case "pointTrack": points[0]["track"] = -1
        case "duplicateRange":
            var duplicate = points[0]
            duplicate["id"] = UUID().uuidString
            points.append(duplicate)
        case "stats": topics[0]["totalSec"] = 99
        case "edgeId": edges[1]["id"] = edges[0]["id"]
        case "edgePoint": edges[0]["pointId"] = "missing"
        case "branchParent": topics[2]["parentId"] = topics[0]["id"]
        case "forwardReturn": edges[0]["type"] = "return"
        case "confidence": edges[0]["confidence"] = 2
        case "until": json["untilSec"] = 0
        case "name": topics[0]["label"] = ""
        default: Issue.record("The test fault is unknown.")
        }
        json["topics"] = topics
        json["points"] = points
        json["edges"] = edges
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(TopicGraph.self, from: data) }
        try data.write(to: store.fileURL(for: meetingId))
        let result = store.load(meetingId: meetingId)
        #expect(result.graph == TopicGraph(meetingId: meetingId))
        #expect(result.error?.isEmpty == false)
    }
}
