import SwiftUI
import TranskribeCore

struct TopicGraphCard: View {
    let topic: TopicGraphTopic
    let pointCount: Int
    let kindCounts: [TopicPointKind: Int]
    let isCurrent: Bool
    let isLive: Bool
    var isHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if isCurrent {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    Text(isLive ? "CURRENT" : "LATEST")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(topic.parentId == nil ? "TOPIC" : "SIDE TOPIC")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(pointCount) \(pointCount == 1 ? "point" : "points")")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10, weight: .semibold))
            Text(topic.label)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                badge(.question, label: "Questions", icon: "questionmark.circle", color: .indigo)
                badge(.decision, label: "Decisions", icon: "checkmark.seal", color: .teal)
                badge(.action, label: "Actions", icon: "arrow.right.circle", color: .orange)
            }
            Text("\(timestamp(topic.firstSec)) – \(timestamp(topic.lastSec))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(isCurrent || isHighlighted ? Color.accentColor : Color.primary.opacity(0.12),
                          lineWidth: isCurrent || isHighlighted ? 2 : 1))
        .shadow(color: .black.opacity(isCurrent ? 0.08 : 0.03), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .help(topic.summary.isEmpty ? topic.label : "\(topic.label)\n\(topic.summary)")
    }

    @ViewBuilder
    private func badge(_ kind: TopicPointKind, label: String, icon: String, color: Color) -> some View {
        if let count = kindCounts[kind], count > 0 {
            Label("\(count)", systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color.opacity(0.09), in: Capsule())
                .accessibilityLabel("\(label): \(count)")
                .help("\(label): \(count)")
        }
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
