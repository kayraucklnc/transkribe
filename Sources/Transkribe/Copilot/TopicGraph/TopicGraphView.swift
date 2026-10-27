import SwiftUI
import TranskribeCore

struct TopicGraphView: View {
    let transcript: Transcript
    let isLive: Bool
    @Environment(AppModel.self) private var model
    @State private var savedGraph: TopicGraph?
    @State private var loadError: String?
    @State private var scene: TopicGraphScene?

    private var controller: LiveTopicGraphController? { model.topicGraphs[transcript.id] }
    private var graph: TopicGraph? { controller?.graph ?? savedGraph }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let notice = controller?.notice ?? loadError {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.orange.opacity(0.08))
            }
            if let scene, !scene.layout.cards.isEmpty || scene.layout.draftCard != nil {
                TopicGraphCanvas(scene: scene, isLive: isLive)
            } else if graph == nil && !isLive && loadError == nil {
                ProgressView("Loading topic graph…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No topics yet", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text(emptyMessage)
                }
            }
        }
        .background(Theme.canvas)
        .task(id: "\(transcript.id)-\(isLive)-\(controller != nil)") {
            guard !isLive, controller == nil else { return }
            let id = transcript.id
            let store = TopicGraphStore(rootDirectory: model.store.rootDirectory)
            let result = await Task.detached(priority: .userInitiated) { store.load(meetingId: id) }.value
            guard !Task.isCancelled else { return }
            savedGraph = result.graph
            loadError = result.error.map { "The saved topic graph is unavailable. \($0)" }
        }
        .task(id: graph) {
            guard let graph else {
                scene = nil
                return
            }
            let updated = await Task.detached(priority: .userInitiated) { TopicGraphScene(graph: graph) }.value
            guard !Task.isCancelled else { return }
            scene = updated
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(Color.accentColor)
            Text("Topic graph").font(.headline)
            if isLive {
                Label("Live", systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.record)
            }
            Spacer()
            let lag = graph?.lagRecords.last { $0.namedAt != nil }?.namedLag
            Text(lag.map { String(format: "Speech → named %.1f s", $0) } ?? "Speech → named —")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.card, in: Capsule())
                .help("The latest batch with a valid topic name. Batches without a name are excluded.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var emptyMessage: String {
        if controller?.notice != nil || loadError != nil { return "The graph notice gives more information." }
        if controller != nil { return "Topics appear as speech arrives. Pending text appears in a draft card." }
        if isLive { return "Enable the topic graph in Settings before you start a recording." }
        return "This meeting has no saved topics. Enable the topic graph before your next recording."
    }
}

struct TopicGraphScene: Sendable {
    let graph: TopicGraph
    let layout: TopicGraphLayout
    let topics: [String: TopicGraphTopic]
    let points: [String: [TopicGraphPoint]]
    let kindCounts: [String: [TopicPointKind: Int]]

    init(graph: TopicGraph) {
        self.graph = graph
        layout = TopicGraphLayout(graph: graph)
        topics = Dictionary(uniqueKeysWithValues: graph.topics.map { ($0.id, $0) })
        points = Dictionary(grouping: graph.points, by: \.topicId)
        kindCounts = points.mapValues { points in
            points.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
        }
    }
}
