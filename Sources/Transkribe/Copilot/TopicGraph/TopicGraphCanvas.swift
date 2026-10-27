import SwiftUI
import TranskribeCore

struct TopicGraphCanvas: View {
    let scene: TopicGraphScene
    let isLive: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            edges
                            ForEach(scene.layout.cards) { card in
                                if let topic = scene.topics[card.id] {
                                    TopicGraphCard(topic: topic,
                                        pointCount: scene.points[card.id]?.count ?? 0,
                                        kindCounts: scene.kindCounts[card.id] ?? [:],
                                        isCurrent: card.id == scene.graph.currentTopicId, isLive: isLive)
                                        .frame(width: card.frame.width, height: card.frame.height)
                                        .id(card.id)
                                        .position(x: card.frame.midX, y: card.frame.midY)
                                }
                            }
                            if let draft = scene.layout.draftCard {
                                draftCard
                                    .frame(width: draft.frame.width, height: draft.frame.height)
                                    .position(x: draft.frame.midX, y: draft.frame.midY)
                            }
                        }
                        .frame(width: max(scene.layout.size.width, geometry.size.width),
                               height: max(scene.layout.size.height, geometry.size.height), alignment: .topLeading)
                    }
                }
                HStack(spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            Label("Shift", systemImage: "arrow.right")
                            Label("Side topic", systemImage: "arrow.turn.down.right")
                            Label("Return / merge", systemImage: "arrow.uturn.backward")
                        }
                        Text("Scroll to explore")
                    }
                    Spacer(minLength: 0)
                    Button(isLive ? "Current topic" : "Latest topic") {
                        if let id = scene.graph.currentTopicId {
                            withAnimation(Theme.spring) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
        }
    }

    private var edges: some View {
        Canvas { context, _ in
            for edge in scene.layout.edges {
                guard let start = edge.waypoints.first, let tip = edge.waypoints.last,
                      let previous = edge.waypoints.dropLast().last else { continue }
                var path = Path()
                path.move(to: start)
                for point in edge.waypoints.dropFirst() { path.addLine(to: point) }
                let color: Color = switch edge.type {
                case .shift: .secondary
                case .branch: .teal
                case .return: .indigo
                case .merge: .orange
                }
                context.stroke(path, with: .color(color.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                       dash: edge.type == .return || edge.type == .merge ? [5, 4] : []))
                let angle = atan2(tip.y - previous.y, tip.x - previous.x)
                var arrow = Path()
                arrow.move(to: CGPoint(x: tip.x - 7 * cos(angle - .pi / 6),
                                      y: tip.y - 7 * sin(angle - .pi / 6)))
                arrow.addLine(to: tip)
                arrow.addLine(to: CGPoint(x: tip.x - 7 * cos(angle + .pi / 6),
                                         y: tip.y - 7 * sin(angle + .pi / 6)))
                context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Draft · listening", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(scene.graph.draft)
                .font(.callout)
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .opacity(0.6)
        .accessibilityElement(children: .combine)
        .help(scene.graph.draft)
    }
}
