import SwiftUI
import TranskribeCore

struct AgentAnswerView: View {
    let message: AIMessage

    var body: some View {
        AssistantBubble {
            VStack(alignment: .leading, spacing: 8) {
                AgentAnswerMetadata(message: message)
                MarkdownView(markdown: message.text)
            }
        }
    }
}

private struct AgentAnswerMetadata: View {
    let message: AIMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("Agent", systemImage: "person.crop.circle.badge.checkmark")
                    .fontWeight(.semibold)
                if message.isFinal != true {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    Text("In progress")
                } else {
                    Text("Final")
                }
            }
            Text("Sent \(time(message.agentTimings?.sentAt)) → Read \(time(message.agentTimings?.firstReadAt))\nFirst take \(time(message.agentTimings?.firstTakeAt)) → Final \(time(message.agentTimings?.finalAt))")
                .font(.caption2.monospacedDigit())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        if let sent = message.agentTimings?.sentAt, date != sent {
            return String(format: "+%.1f s", date.timeIntervalSince(sent))
        }
        return date.formatted(date: .omitted, time: .standard)
    }
}
