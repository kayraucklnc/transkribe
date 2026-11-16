import SwiftUI
import TranskribeCore

struct TopicGraphCanvas: View {
    let scene: TopicGraphScene
    let isLive: Bool
    let selectedTopicId: String?
    /// Changes when the user asks to see the current topic.
    let focusRequest: Int
    let onSelect: (String) -> Void
    @State private var hoveredTopicId: String?
    /// While live, new topics scroll into view unless the user scrolled up to read.
    @State private var followsCurrent = true

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                // The layout wraps to the pane width; it only scrolls sideways in a pane narrower than a card.
                ScrollView([.vertical, .horizontal]) {
                    graph
                        .frame(width: scene.layout.size.width, height: scene.layout.size.height, alignment: .topLeading)
                        // Room to scroll the last line above the player or recording bar.
                        .padding(.bottom, ConversationView.bottomBarClearance)
                        .frame(minWidth: geometry.size.width, alignment: .topLeading)
                }
                .modifier(TracksScrollEnd(isAtEnd: $followsCurrent))
                .onAppear { if isLive { showCurrent(proxy, animated: false) } }
                .onChange(of: scene.layout.currentCardId) { _, _ in if isLive, followsCurrent { showCurrent(proxy) } }
                .onChange(of: scene.layout.size) { _, _ in if isLive, followsCurrent { showCurrent(proxy) } }
                .onChange(of: focusRequest) { _, _ in
                    followsCurrent = true
                    showCurrent(proxy)
                }
            }
        }
    }

    private var graph: some View {
        let highlighted = hoveredTopicId.map { TopicGraphInteraction.touches(topicId: $0, in: scene.graph) }
        return ZStack(alignment: .topLeading) {
            edges(touches: highlighted)
            ForEach(scene.layout.cards) { card in
                if let topic = scene.topics[card.topicId] {
                    Button { onSelect(card.topicId) } label: {
                        TopicGraphCard(topic: topic, revisit: card.revisit,
                                       parentLabel: topic.parentId.flatMap { scene.topics[$0]?.label },
                                       isCurrent: card.id == scene.layout.currentCardId, isLive: isLive,
                                       isSelected: selectedTopicId == card.topicId, isCompact: card.isCompact)
                    }
                    .buttonStyle(.plain)
                    .frame(width: card.frame.width, height: card.frame.height)
                    .contentShape(RoundedRectangle(cornerRadius: card.isCompact ? 10 : 14))
                    .opacity(highlighted.map { $0.topicIds.contains(card.topicId) ? 1 : 0.25 } ?? 1)
                    .id(card.id)
                    .position(x: card.frame.midX, y: card.frame.midY)
                }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if case .topic(let id) = TopicGraphInteraction.hitTest(at: location, regions: scene.hitRegions) {
                    hoveredTopicId = id
                } else {
                    hoveredTopicId = nil
                }
            case .ended:
                hoveredTopicId = nil
            }
        }
        .animation(.easeOut(duration: 0.15), value: hoveredTopicId)
    }

    private func showCurrent(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let id = scene.layout.currentCardId else { return }
        if animated {
            withAnimation(Theme.spring) { proxy.scrollTo(id, anchor: .center) }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func edges(touches: TopicGraphInteraction.Touches?) -> some View {
        Canvas { context, _ in
            for edge in scene.layout.edges {
                var path = Path()
                path.move(to: edge.start)
                for segment in edge.segments {
                    path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                }
                let isHighlighted = touches?.edgeIds.contains(edge.id) == true
                // No arrowheads: every link runs forward in time, left to right and then down.
                let opacity = touches == nil ? 0.7 : (isHighlighted ? 1 : 0.12)
                let color = Self.color(for: edge.type).opacity(opacity)
                let isDashed = edge.type == .return || edge.type == .merge
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: isHighlighted ? 3.5 : 2.75, lineCap: .round,
                                                  lineJoin: .round, dash: isDashed ? [7, 6] : []))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func color(for type: TopicEdgeType) -> Color {
        switch type {
        case .shift: .secondary
        case .branch: .teal
        case .return: .indigo
        case .merge: .orange
        }
    }
}

/// Reports whether the scroll view shows its last line. macOS 14 cannot observe scrolling, so there
/// the graph always follows the current topic.
private struct TracksScrollEnd: ViewModifier {
    @Binding var isAtEnd: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 160
            } action: { _, atEnd in
                isAtEnd = atEnd
            }
        } else {
            content
        }
    }
}
