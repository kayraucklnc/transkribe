import SwiftUI
import TranskribeCore

struct TopicGraphDetails: View {
    let topic: TopicGraphTopic
    let points: [TopicGraphPoint]
    let graph: TopicGraph
    let speakerName: (Int) -> String
    let onJump: (TopicGraphInteraction.Target) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Topic details").font(.headline)
                Spacer()
                Button("Close topic details", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(topic.label).font(.title3.weight(.semibold))
                    Text(span(from: topic.firstSec, to: topic.lastSec))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(topic.summary.isEmpty ? "No summary yet." : topic.summary)
                        .font(.callout)
                        .textSelection(.enabled)
                    Button { onJump(.topic(topic.id)) } label: {
                        Label("Go to start", systemImage: "text.alignleft")
                    }
                    .buttonStyle(.bordered)
                    Divider()
                    Text("\(points.count) \(points.count == 1 ? "point" : "points")")
                        .font(.subheadline.weight(.semibold))
                    ForEach(points) { point in
                        pointButton(point)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .padding(.bottom, 80)
            }
        }
        .background(Theme.canvas)
    }

    private func pointButton(_ point: TopicGraphPoint) -> some View {
        let start = graph.meetingTime(for: point)
        let speaker = point.speaker.map(speakerName) ?? "Unknown speaker"
        return Button { onJump(.point(point.id)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(speaker).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Text(point.kind.rawValue.capitalized)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.caption)
                Text(point.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Label(span(from: start, to: start + point.end - point.start), systemImage: "text.alignleft")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Show this point in the transcript")
    }

    private func span(from start: TimeInterval, to end: TimeInterval) -> String {
        "\(TranscriptFormatter.timestamp(start)) – \(TranscriptFormatter.timestamp(end))"
    }
}
