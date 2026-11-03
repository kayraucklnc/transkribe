import Foundation

public struct TopicGraphLoadResult: Sendable {
    public let graph: TopicGraph
    public let error: String?
}

/// Stores graph.json in the same meeting folder as transcript.json.
public struct TopicGraphStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// A failed load returns an empty graph and an error for the caller to display.
    public func load(meetingId: UUID) -> TopicGraphLoadResult {
        do {
            let data = try Data(contentsOf: fileURL(for: meetingId))
            let graph = try JSONDecoder().decode(TopicGraph.self, from: data)
            guard graph.meetingId == meetingId else { throw TopicGraphError.invalidGraph }
            return .init(graph: graph, error: nil)
        } catch {
            return .init(graph: TopicGraph(meetingId: meetingId), error: error.localizedDescription)
        }
    }

    public func save(_ graph: TopicGraph) throws {
        let file = fileURL(for: graph.meetingId)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(graph).write(to: file, options: .atomic)
    }

    public func fileURL(for meetingId: UUID) -> URL {
        rootDirectory.appendingPathComponent(meetingId.uuidString, isDirectory: true)
            .appendingPathComponent("graph.json")
    }
}
