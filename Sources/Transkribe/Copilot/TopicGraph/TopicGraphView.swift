import SwiftUI
import TranskribeCore

struct TopicGraphView: View {
    let transcript: Transcript
    let isLive: Bool
    let onJump: (TimeInterval) -> Void
    @Environment(AppModel.self) private var model
    @State private var savedGraph: TopicGraph?
    @State private var loadError: String?
    @State private var scene: TopicGraphScene?
    @State private var selectedTopicId: String?
    @State private var focusRequest = 0
    /// The canvas width the graph wraps at.
    @State private var width: CGFloat = 0

    private var controller: LiveTopicGraphController? { model.topicGraphs[transcript.id] }
    private var graph: TopicGraph? { controller?.graph ?? savedGraph }
    /// Pending text changes many times a second and never moves a card, so the layout ignores it.
    private var structure: TopicGraph? { graph.map { var graph = $0; graph.draft = ""; return graph } }
    private var draft: String { (graph?.draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

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
            if isLive, !draft.isEmpty {
                TopicGraphListening(draft: draft)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { width = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, newWidth in width = newWidth }
                    }
                }
        }
        .background(Theme.canvas)
        .inspector(isPresented: Binding(
            get: { selectedTopicId != nil },
            set: { if !$0 { selectedTopicId = nil } }
        )) {
            if let scene, let id = selectedTopicId, let topic = scene.topics[id] {
                TopicGraphDetails(topic: topic, points: scene.points[id] ?? [], graph: scene.graph,
                    speakerName: { transcript.name(of: $0, people: model.people) },
                    onJump: { target in
                        if let time = TopicGraphInteraction.jumpTime(to: target, in: scene.graph) { onJump(time) }
                    }, onClose: { selectedTopicId = nil })
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 400)
            }
        }
        .task(id: "\(transcript.id)-\(isLive)-\(controller != nil)") {
            guard !isLive, controller == nil else { return }
            let id = transcript.id
            let store = TopicGraphStore(rootDirectory: model.store.rootDirectory)
            let result = await Task.detached(priority: .userInitiated) { store.load(meetingId: id) }.value
            guard !Task.isCancelled else { return }
            savedGraph = result.graph
            loadError = result.error.map { "The saved topic graph is unavailable. \($0)" }
        }
        .task(id: SceneKey(graph: structure, width: width.rounded())) {
            guard let structure else {
                scene = nil
                return
            }
            guard width > 0 else { return }
            let width = width
            let updated = await Task.detached(priority: .userInitiated) {
                TopicGraphScene(graph: structure, width: width)
            }.value
            guard !Task.isCancelled else { return }
            scene = updated
        }
    }

    @ViewBuilder
    private var content: some View {
        if let scene, !scene.layout.cards.isEmpty {
            TopicGraphCanvas(scene: scene, isLive: isLive, selectedTopicId: selectedTopicId,
                             focusRequest: focusRequest) { selectedTopicId = $0 }
        } else if isLoading {
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

    /// Still reading graph.json, or still laying out topics that already exist.
    private var isLoading: Bool {
        if let graph { return !graph.topics.isEmpty }
        return !isLive && loadError == nil
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
            Spacer(minLength: 12)
            if let lag = graph?.lagRecords.last(where: { $0.namedAt != nil })?.namedLag {
                Text(String(format: "Named %.1f s after speech", lag))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help("The latest batch with a valid topic name. Batches without a name are excluded.")
            }
            if scene?.layout.cards.isEmpty == false {
                Button { focusRequest += 1 } label: {
                    Label(isLive ? "Current topic" : "Latest topic", systemImage: "scope")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.large)
                .help(isLive ? "Show the current topic" : "Show the latest topic")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyMessage: String {
        if controller?.notice != nil || loadError != nil { return "The graph notice gives more information." }
        if controller != nil { return "Topics appear as speech arrives." }
        if isLive { return "Enable the topic graph in Settings before you start a recording." }
        return "This meeting has no saved topics. Enable the topic graph before your next recording."
    }
}

/// Speech that is not routed to a topic yet. The newest words stay visible.
struct TopicGraphListening: View {
    let draft: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(draft)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Listening: \(draft)")
        .help(draft)
    }
}

/// The layout depends on the graph without its pending text, and on the width it wraps at.
private struct SceneKey: Equatable {
    let graph: TopicGraph?
    let width: CGFloat
}

struct TopicGraphScene: Sendable {
    let graph: TopicGraph
    let layout: TopicGraphLayout
    let hitRegions: [TopicGraphInteraction.Region]
    let topics: [String: TopicGraphTopic]
    let points: [String: [TopicGraphPoint]]

    init(graph: TopicGraph, width: CGFloat) {
        self.graph = graph
        layout = TopicGraphLayout(graph: graph, width: width)
        hitRegions = TopicGraphInteraction.regions(in: layout)
        topics = Dictionary(uniqueKeysWithValues: graph.topics.map { ($0.id, $0) })
        points = Dictionary(grouping: graph.points.sorted {
            let left = graph.meetingTime(for: $0), right = graph.meetingTime(for: $1)
            return left == right ? $0.track < $1.track : left < right
        }, by: \.topicId)
    }
}
