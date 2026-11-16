import SwiftUI
import TranskribeCore

/// The meeting's structure: main topics left to right on one spine, side topics hanging beneath
/// the topic they branched from. Each topic appears once; time and returns live in the timeline.
struct TopicMapView: View {
    let scene: TopicGraphScene
    let isLive: Bool
    let selectedTopicId: String?
    /// How much recent conversation stays in focus. Older topics fold into compact history; `nil` shows everything.
    let span: TimeInterval?
    /// Changes when the user asks to see the current topic.
    let focusRequest: Int
    let onSelect: (String) -> Void

    var body: some View {
        let focus = span.map { scene.timeline.focusedTopicIds(in: scene.timeline.window(span: $0)) }
        GeometryReader { geometry in
            TopicMapContent(scene: scene,
                            layout: TopicMapLayout(graph: scene.graph, width: geometry.size.width, focus: focus),
                            isLive: isLive, selectedTopicId: selectedTopicId, focusRequest: focusRequest,
                            onSelect: onSelect)
        }
    }
}

private struct TopicMapContent: View {
    let scene: TopicGraphScene
    let layout: TopicMapLayout
    let isLive: Bool
    let selectedTopicId: String?
    let focusRequest: Int
    let onSelect: (String) -> Void
    @State private var hoveredTopicId: String?

    private var currentId: String? { scene.graph.currentTopicId }

    var body: some View {
        let related = hoveredTopicId.map(relatives(of:))
        let currentPath = currentId.map(ancestors(of:)) ?? []
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    links(related: related, currentPath: currentPath)
                    ForEach(layout.nodes) { node in
                        if let topic = scene.topics[node.id] {
                            Button { onSelect(node.id) } label: {
                                TopicMapNode(topic: topic, row: scene.rowsById[node.id], isMain: node.depth == 0,
                                             isDormant: node.isDormant,
                                             isCurrent: node.id == currentId, isLive: isLive,
                                             isSelected: node.id == selectedTopicId)
                            }
                            .buttonStyle(.plain)
                            .frame(width: node.frame.width, height: node.frame.height)
                            .opacity(related.map { $0.contains(node.id) ? 1 : 0.35 } ?? 1)
                            .onHover { inside in
                                if inside { hoveredTopicId = node.id } else if hoveredTopicId == node.id { hoveredTopicId = nil }
                            }
                            .id(node.id)
                            .position(x: node.frame.midX, y: node.frame.midY)
                        }
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                // Room to scroll the last line above the player or recording bar.
                .padding(.bottom, ConversationView.bottomBarClearance)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(.easeOut(duration: 0.15), value: hoveredTopicId)
            }
            .onAppear { showCurrent(proxy, anchor: .center, animated: false) }
            .onChange(of: currentId) { _, _ in if isLive { showCurrent(proxy, anchor: nil) } }
            .onChange(of: focusRequest) { _, _ in showCurrent(proxy, anchor: .center) }
        }
    }

    /// One calm colour for every connector. The branch leading to the current topic is tinted, and
    /// hovering a topic brings out the connectors to its parent and side topics.
    private func links(related: Set<String>?, currentPath: Set<String>) -> some View {
        Canvas { context, _ in
            for link in layout.links {
                var path = Path()
                guard let first = link.segments.first else { continue }
                path.move(to: first.start)
                for segment in link.segments {
                    path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                }
                let isRelated = related.map { $0.contains(link.from) && $0.contains(link.to) }
                let leadsToCurrent = link.kind == .branch && currentPath.contains(link.to)
                let color: Color = switch (isRelated, leadsToCurrent) {
                case (false?, _): .primary.opacity(0.08)
                case (true?, _): .primary.opacity(0.55)
                case (nil, true): Color.accentColor.opacity(0.7)
                case (nil, false): .primary.opacity(0.22)
                }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: link.kind == .spine ? 2.5 : 2, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The topic, its parent and its side topics.
    private func relatives(of id: String) -> Set<String> {
        var result: Set<String> = [id]
        if let parent = scene.topics[id]?.parentId { result.insert(parent) }
        result.formUnion(scene.graph.topics.filter { $0.parentId == id }.map(\.id))
        return result
    }

    /// The topic and every topic above it, up to its main topic.
    private func ancestors(of id: String) -> Set<String> {
        var result: Set<String> = []
        var next: String? = id
        while let current = next, result.insert(current).inserted {
            next = scene.topics[current]?.parentId
        }
        return result
    }

    private func showCurrent(_ proxy: ScrollViewProxy, anchor: UnitPoint?, animated: Bool = true) {
        guard let id = currentId else { return }
        if animated {
            withAnimation(Theme.spring) { proxy.scrollTo(id, anchor: anchor) }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }
}

/// A topic on the map: its name, then how long it was discussed and how often it came up.
private struct TopicMapNode: View {
    let topic: TopicGraphTopic
    let row: TopicTimeline.Row?
    let isMain: Bool
    /// A topic the conversation has moved on from: name only, quieter.
    let isDormant: Bool
    let isCurrent: Bool
    let isLive: Bool
    let isSelected: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12) }
    private var isResolved: Bool { row?.isResolved == true }
    private var detail: String {
        let total = TranscriptFormatter.timestamp(row?.totalSec ?? 0)
        guard let visits = row?.visitCount, visits > 1 else { return total }
        return "\(total) · \(visits) times"
    }

    var body: some View {
        if isDormant { dormant } else { card }
    }

    private var dormant: some View {
        Text(topic.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(shape.fill(Theme.card.opacity(0.6)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            .contentShape(shape)
            .help("\(topic.label)\nEarlier topic · \(detail)")
            .accessibilityLabel(topic.label)
            .accessibilityValue("earlier topic, \(detail)")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.label)
                .font(.system(size: isMain ? 14 : 13, weight: isMain ? .semibold : .medium))
                .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor)
                                           : isResolved ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { shape.fill(Theme.card); shape.fill(tint) }
        .overlay(shape.strokeBorder(isCurrent ? Color.accentColor : Color.primary.opacity(0.08),
                                    lineWidth: isCurrent ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            if isCurrent, isLive {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(9)
            }
        }
        .shadow(color: .black.opacity(isCurrent ? 0.12 : 0.05), radius: isCurrent ? 8 : 4, y: 2)
        .contentShape(shape)
        .help(topic.summary.isEmpty ? topic.label : "\(topic.label)\n\(topic.summary)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(topic.label)
        .accessibilityValue([isCurrent ? (isLive ? "current topic" : "latest topic") : nil,
                             isMain ? nil : "side topic", detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tint: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        return isCurrent ? Color.accentColor.opacity(0.08) : .clear
    }
}
