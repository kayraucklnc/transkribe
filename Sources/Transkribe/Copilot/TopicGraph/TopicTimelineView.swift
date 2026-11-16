import SwiftUI
import TranskribeCore

/// The meeting as a sideways sequence diagram: topics as rows, time left to right, and one line that
/// steps from row to row as the conversation moves. Going back to a topic steps back up to its row.
struct TopicTimelineView: View {
    static let rowHeight: CGFloat = 34
    static let barHeight: CGFloat = 12
    static let minimumBarWidth: CGFloat = 4
    static let leadingInset: CGFloat = 20
    static let trailingInset: CGFloat = 28

    let scene: TopicGraphScene
    let isLive: Bool
    let selectedTopicId: String?
    /// How much of the meeting to show, ending now. `nil` shows the whole meeting.
    let span: TimeInterval?
    /// Changes when the user asks to see the current topic.
    let focusRequest: Int
    let onSelect: (String) -> Void
    @State private var hoveredTopicId: String?

    private var timeline: TopicTimeline { scene.timeline }

    var body: some View {
        GeometryReader { geometry in
            let labelWidth = min(240, max(150, geometry.size.width * 0.3))
            let trackWidth = max(80, geometry.size.width - Self.leadingInset - Self.trailingInset - labelWidth - 12)
            let metrics = Metrics(labelWidth: labelWidth, trackWidth: trackWidth, window: timeline.window(span: span))
            VStack(spacing: 0) {
                ruler(metrics)
                Divider().opacity(0.5)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(Array(timeline.rows.enumerated()), id: \.element.id) { index, row in
                                rowView(row, index: index, metrics: metrics)
                            }
                        }
                        .background(alignment: .topLeading) { paths(metrics) }
                        .padding(.top, 6)
                        // Room to scroll the last row above the player or recording bar.
                        .padding(.bottom, ConversationView.bottomBarClearance)
                    }
                    .onAppear { showCurrent(proxy, anchor: .center, animated: false) }
                    .onChange(of: timeline.currentTopicId) { _, _ in if isLive { showCurrent(proxy, anchor: nil) } }
                    .onChange(of: focusRequest) { _, _ in showCurrent(proxy, anchor: .center) }
                }
            }
        }
    }

    struct Metrics {
        let labelWidth: CGFloat
        let trackWidth: CGFloat
        let window: ClosedRange<TimeInterval>
        var trackOrigin: CGFloat { TopicTimelineView.leadingInset + labelWidth + 12 }
    }

    // MARK: Rows

    private func rowView(_ row: TopicTimeline.Row, index: Int, metrics: Metrics) -> some View {
        let topic = scene.topics[row.id]
        let isCurrent = row.id == timeline.currentTopicId
        let isSelected = row.id == selectedTopicId
        let isHovered = row.id == hoveredTopicId
        let isInView = (scene.visitsByRow[index] ?? []).contains { $0.end >= metrics.window.lowerBound }
        return Button { onSelect(row.id) } label: {
            HStack(spacing: 12) {
                label(row, topic: topic, isCurrent: isCurrent)
                    .frame(width: metrics.labelWidth, alignment: .leading)
                track(row, index: index, isCurrent: isCurrent, isEmphasised: isHovered || isSelected, metrics: metrics)
                    .frame(width: metrics.trackWidth, height: Self.rowHeight, alignment: .leading)
            }
            .padding(.leading, Self.leadingInset)
            .padding(.trailing, Self.trailingInset)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
            .background(rowTint(isCurrent: isCurrent, isSelected: isSelected, isHovered: isHovered))
            // Topics with nothing in the window stay in the outline, quieter.
            .opacity(isInView || isSelected || isHovered ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredTopicId = row.id } else if hoveredTopicId == row.id { hoveredTopicId = nil }
        }
        .help(help(for: row, topic: topic))
        .accessibilityLabel(accessibilityLabel(for: row, topic: topic, isCurrent: isCurrent))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(row.id)
    }

    private func label(_ row: TopicTimeline.Row, topic: TopicGraphTopic?, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            Text(topic?.label ?? "Topic")
                .font(.system(size: 13, weight: isCurrent ? .semibold : (row.depth == 0 ? .medium : .regular)))
                .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor)
                                           : row.isResolved ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(TranscriptFormatter.timestamp(row.totalSec))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        // Side topics indent under their parent, like an outline.
        .padding(.leading, CGFloat(row.depth) * 16)
    }

    private func track(_ row: TopicTimeline.Row, index: Int, isCurrent: Bool, isEmphasised: Bool,
                       metrics: Metrics) -> some View {
        let visits = scene.visitsByRow[index] ?? []
        let last = timeline.visits.last
        return ZStack(alignment: .leading) {
            ForEach(visits) { visit in
                let x = timeline.x(for: visit.start, in: metrics.window, width: metrics.trackWidth)
                let width = max(Self.minimumBarWidth,
                                timeline.x(for: visit.end, in: metrics.window, width: metrics.trackWidth) - x)
                Capsule()
                    .fill(barColor(isNow: visit.id == last?.id, isCurrent: isCurrent, isEmphasised: isEmphasised))
                    .frame(width: width, height: Self.barHeight)
                    .offset(x: x)
            }
            if isLive, let last, last.row == index {
                NowDot()
                    .offset(x: timeline.x(for: last.end, in: metrics.window, width: metrics.trackWidth) - 5)
            }
        }
        // Visits before the window slide out of view on the left.
        .frame(width: metrics.trackWidth, alignment: .leading)
        .clipShape(Rectangle().inset(by: -6))
        .mask(earlierFade(width: metrics.trackWidth, leading: 0, window: metrics.window).padding(-6))
    }

    private func barColor(isNow: Bool, isCurrent: Bool, isEmphasised: Bool) -> Color {
        if isNow { return .accentColor }
        // Earlier visits to the current topic stay tinted, so you can see you have been here before.
        if isCurrent { return Color.accentColor.opacity(0.45) }
        return Color.primary.opacity(isEmphasised ? 0.5 : 0.22)
    }

    private func rowTint(isCurrent: Bool, isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if isCurrent { return Color.accentColor.opacity(0.07) }
        return isHovered ? Color.primary.opacity(0.04) : .clear
    }

    // MARK: Path

    /// The conversation's path: a step from row to row at each switch, plus faint time guides.
    private func paths(_ metrics: Metrics) -> some View {
        let rowCount = timeline.rows.count
        return Canvas { context, _ in
            let height = CGFloat(rowCount) * Self.rowHeight
            context.clip(to: Path(CGRect(x: metrics.trackOrigin, y: 0, width: metrics.trackWidth + 6, height: height)))
            for tick in timeline.ticks(in: metrics.window, width: metrics.trackWidth) where tick > metrics.window.lowerBound {
                let x = metrics.trackOrigin + timeline.x(for: tick, in: metrics.window, width: metrics.trackWidth)
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: height)) },
                               with: .color(.primary.opacity(0.05)), lineWidth: 1)
            }
            let visits = timeline.visits
            for (index, (from, to)) in zip(visits, visits.dropFirst()).enumerated() where from.row != to.row {
                guard to.start >= metrics.window.lowerBound else { continue }
                let x = metrics.trackOrigin + timeline.x(for: to.start, in: metrics.window, width: metrics.trackWidth)
                let path = Self.step(at: x, from: Self.centre(of: from.row), to: Self.centre(of: to.row))
                let isLatest = index == visits.count - 2
                context.stroke(path, with: .color(isLatest ? Color.accentColor.opacity(0.8) : .primary.opacity(0.3)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: CGFloat(rowCount) * Self.rowHeight)
        .mask(earlierFade(width: metrics.trackWidth, leading: metrics.trackOrigin, window: metrics.window))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func centre(of row: Int) -> CGFloat { CGFloat(row) * rowHeight + rowHeight / 2 }

    /// A straight vertical step at `x`, from the end of one bar to the start of the next. The rounded
    /// bar ends sit on top of it, so the path reads as one line moving between rows.
    private static func step(at x: CGFloat, from y1: CGFloat, to y2: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x, y: y1))
            path.addLine(to: CGPoint(x: x, y: y2))
        }
    }

    /// Bars and steps fade out at the left edge when earlier parts of the meeting are out of view.
    private func earlierFade(width: CGFloat, leading: CGFloat, window: ClosedRange<TimeInterval>) -> LinearGradient {
        let fade = window.lowerBound > 0 ? min(0.2, 32 / max(width, 1)) : 0
        let start = leading / max(width + leading, 1)
        return LinearGradient(stops: [.init(color: .black.opacity(window.lowerBound > 0 ? 0 : 1), location: start),
                                      .init(color: .black, location: start + fade)],
                              startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Ruler

    private func ruler(_ metrics: Metrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(timeline.ticks(in: metrics.window, width: metrics.trackWidth), id: \.self) { tick in
                let x = timeline.x(for: tick, in: metrics.window, width: metrics.trackWidth)
                if x <= metrics.trackWidth - 24 || tick == metrics.window.lowerBound {
                    Text(TranscriptFormatter.timestamp(tick))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .offset(x: metrics.trackOrigin + x)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    // MARK: Scrolling and text

    private func showCurrent(_ proxy: ScrollViewProxy, anchor: UnitPoint?, animated: Bool = true) {
        guard let id = timeline.currentTopicId else { return }
        if animated {
            withAnimation(Theme.spring) { proxy.scrollTo(id, anchor: anchor) }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }

    private func parentLabel(of topic: TopicGraphTopic?) -> String? {
        topic?.parentId.flatMap { scene.topics[$0]?.label }
    }

    private func help(for row: TopicTimeline.Row, topic: TopicGraphTopic?) -> String {
        let visits = row.visitCount == 1 ? "Discussed once" : "Discussed \(row.visitCount) times"
        return [topic?.label, parentLabel(of: topic).map { "Side topic of \($0)" },
                "\(visits), \(TranscriptFormatter.timestamp(row.totalSec)) in total",
                topic.flatMap { $0.summary.isEmpty ? nil : $0.summary }]
            .compactMap { $0 }.joined(separator: "\n")
    }

    private func accessibilityLabel(for row: TopicTimeline.Row, topic: TopicGraphTopic?, isCurrent: Bool) -> String {
        [topic?.label, parentLabel(of: topic).map { "side topic of \($0)" },
         isCurrent ? (isLive ? "current topic" : "latest topic") : nil,
         row.visitCount == 1 ? "discussed once" : "discussed \(row.visitCount) times",
         "\(TranscriptFormatter.timestamp(row.totalSec)) in total"]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// Marks where the conversation is right now while recording.
private struct NowDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Theme.canvas, lineWidth: 2))
            .phaseAnimator([false, true]) { dot, pulse in
                dot.shadow(color: Color.accentColor.opacity(pulse ? 0.7 : 0), radius: pulse ? 6 : 0)
            } animation: { _ in .easeInOut(duration: 0.9) }
            .accessibilityHidden(true)
    }
}
