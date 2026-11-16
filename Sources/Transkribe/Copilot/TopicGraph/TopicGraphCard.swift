import SwiftUI
import TranskribeCore

/// A topic in the graph: its name and when it was discussed. Compact cards (older topics in long
/// meetings) show the name only. A revisit marks the moment the conversation went back to a topic.
struct TopicGraphCard: View {
    let topic: TopicGraphTopic
    let revisit: TopicEdgeType?
    /// The side topic's parent, for the tooltip.
    let parentLabel: String?
    let isCurrent: Bool
    let isLive: Bool
    let isSelected: Bool
    let isCompact: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: isCompact ? 10 : 14) }
    private var span: String {
        "\(TranscriptFormatter.timestamp(topic.firstSec)) – \(TranscriptFormatter.timestamp(topic.lastSec))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let revisit {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TopicGraphCanvas.color(for: revisit))
                        .accessibilityHidden(true)
                } else if isCurrent {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Text(topic.label)
                    .font(.system(size: isCompact ? 12 : 14, weight: revisit == nil ? .semibold : .medium))
                    .foregroundStyle(revisit == nil ? .primary : .secondary)
                    .lineLimit(isCompact ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isCompact {
                Spacer(minLength: 0)
                Text(span)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, isCompact ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCompact ? .leading : .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Theme.card, in: shape)
        .overlay(shape.strokeBorder(isCurrent ? Color.accentColor : Color.primary.opacity(isSelected ? 0.25 : 0.1),
                                    style: StrokeStyle(lineWidth: isCurrent ? 2 : 1, dash: revisit == nil ? [] : [4, 3])))
        .shadow(color: .black.opacity(isCurrent ? 0.1 : 0.04), radius: 6, y: 2)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue([isCurrent ? (isLive ? "Current topic" : "Latest topic") : nil, span]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityTitle: String {
        switch revisit {
        case .return: "Back to \(topic.label)"
        case .merge: "Back to \(topic.label) after the side topic"
        default: topic.label
        }
    }

    private var help: String {
        let context = parentLabel.map { "Side topic of \($0)" }
        return [accessibilityTitle, context, topic.summary.isEmpty ? nil : topic.summary, span]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
