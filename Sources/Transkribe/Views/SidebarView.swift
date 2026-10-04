import SwiftUI
import TranskribeCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.filteredTranscripts) { transcript in
                SidebarRow(transcript: transcript, progress: model.progress[transcript.id])
                    .tag(transcript.id)
                    .contextMenu {
                        Button("Copy Transcript") { model.copyText(of: transcript.id) }
                        Button("Show in Finder") { model.revealInFinder(transcript.id) }
                        Divider()
                        Button("Delete", role: .destructive) { model.delete(transcript.id) }
                    }
            }
        }
        .onDeleteCommand {
            if let id = model.selection { model.delete(id) }
        }
        .overlay {
            if model.filteredTranscripts.isEmpty {
                Text(model.query.isEmpty ? "No transcripts yet" : "No matches")
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ModelStatusView()
        }
    }
}

private struct SidebarRow: View {
    let transcript: Transcript
    let progress: Double?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(transcript.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            statusBadge
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        let date = transcript.createdAt.formatted(.relative(presentation: .named))
        return "\(date) · \(TranscriptFormatter.timestamp(transcript.duration))"
    }

    @ViewBuilder private var statusBadge: some View {
        switch transcript.status {
        case .transcribing:
            Text((progress ?? 0).formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .pending:
            Image(systemName: "clock").foregroundStyle(.secondary).font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
        case .done:
            EmptyView()
        }
    }
}

/// Shows first-run model download / preparation progress.
private struct ModelStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.modelPreparation {
        case .downloading(let fraction):
            status("Downloading speech model (one time)…", value: fraction)
        case .loading(firstTime: true):
            status("Optimizing speech model for this Mac…", detail: "First launch only. This takes a minute or two.", value: nil)
        case .loading(firstTime: false):
            status("Loading speech model…", value: nil)
        case .ready, nil:
            EmptyView()
        }
    }

    private func status(_ text: String, detail: String? = nil, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.caption).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
            if let value {
                ProgressView(value: value).controlSize(.small)
            } else {
                ProgressView().progressViewStyle(.linear).controlSize(.small)
            }
        }
        .padding(12)
        .background(.bar)
    }
}
