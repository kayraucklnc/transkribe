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
    @AppStorage("topicGraphStyle") private var style = TopicGraphStyle.timeline
    /// Seconds of the meeting the timeline shows, ending now; 0 shows the whole meeting.
    @AppStorage("topicTimelineSpan") private var span = 900

    private var controller: LiveTopicGraphController? { model.topicGraphs[transcript.id] }
    private var graph: TopicGraph? { controller?.graph ?? savedGraph }
    /// Pending text changes many times a second and never changes the timeline, so the timeline ignores it.
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
        .task(id: structure) {
            guard let structure else {
                scene = nil
                return
            }
            let updated = await Task.detached(priority: .userInitiated) { TopicGraphScene(graph: structure) }.value
            guard !Task.isCancelled else { return }
            scene = updated
        }
    }

    @ViewBuilder
    private var content: some View {
        if let scene, !scene.timeline.rows.isEmpty {
            switch style {
            case .timeline:
                TopicTimelineView(scene: scene, isLive: isLive, selectedTopicId: selectedTopicId,
                                  span: span > 0 ? TimeInterval(span) : nil,
                                  focusRequest: focusRequest) { selectedTopicId = $0 }
            case .map:
                TopicMapView(scene: scene, isLive: isLive, selectedTopicId: selectedTopicId,
                             span: span > 0 ? TimeInterval(span) : nil,
                             focusRequest: focusRequest) { selectedTopicId = $0 }
            }
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

    /// Still reading graph.json, or still building the timeline for topics that already exist.
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
            if scene?.timeline.rows.isEmpty == false {
                TopicGraphControls(style: $style, span: $span, isLive: isLive) { focusRequest += 1 }
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

enum TopicGraphStyle: String {
    /// Topics as rows, time left to right: how the conversation moved.
    case timeline
    /// Topics as a map: what came up and what branched from what.
    case map
}

/// Switch between the timeline and the map, choose how much recent conversation stays in focus, and jump to now.
struct TopicGraphControls: View {
    static let spans: [(seconds: Int, title: String, short: String)] = [
        (300, "Last 5 minutes", "5 min"), (900, "Last 15 minutes", "15 min"),
        (1_800, "Last 30 minutes", "30 min"), (0, "Whole meeting", "All"),
    ]

    @Binding var style: TopicGraphStyle
    @Binding var span: Int
    let isLive: Bool
    let onShowCurrent: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Show", selection: $span) {
                    ForEach(Self.spans, id: \.seconds) { Text($0.title).tag($0.seconds) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(Self.spans.first { $0.seconds == span }?.short ?? "All", systemImage: "clock")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("How much recent conversation stays in focus. Topics the conversation moved on from fold away.")
            Picker("View", selection: $style) {
                Image(systemName: "chart.bar.xaxis")
                    .accessibilityLabel("Timeline")
                    .help("Timeline: how the conversation moved between topics")
                    .tag(TopicGraphStyle.timeline)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .accessibilityLabel("Map")
                    .help("Map: which topics came up and what branched from what")
                    .tag(TopicGraphStyle.map)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button(action: onShowCurrent) {
                Label(isLive ? "Current topic" : "Latest topic", systemImage: "scope")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .help(isLive ? "Show the current topic" : "Show the latest topic")
        }
    }
}

struct TopicGraphScene: Sendable {
    let graph: TopicGraph
    let timeline: TopicTimeline
    let topics: [String: TopicGraphTopic]
    let points: [String: [TopicGraphPoint]]
    let visitsByRow: [Int: [TopicTimeline.Visit]]
    let rowsById: [String: TopicTimeline.Row]

    init(graph: TopicGraph) {
        self.graph = graph
        timeline = TopicTimeline(graph: graph)
        topics = Dictionary(graph.topics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        points = Dictionary(grouping: graph.points.sorted {
            let left = graph.meetingTime(for: $0), right = graph.meetingTime(for: $1)
            return left == right ? $0.track < $1.track : left < right
        }, by: \.topicId)
        visitsByRow = Dictionary(grouping: timeline.visits, by: \.row)
        rowsById = Dictionary(timeline.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
