import SwiftUI
import TranskribeCore

/// Find in this conversation: matches are highlighted in the bubbles; arrows jump between them.
struct FindBar: View {
    let transcript: Transcript
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var index = 0

    var body: some View {
        @Bindable var model = model
        let hits = TranscriptSearch.hits(in: transcript, query: model.query)
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in conversation", text: $model.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 220)
                .onSubmit { move(1, in: hits) }
            Text(hits.isEmpty ? (model.query.isEmpty ? "" : "No matches") : "\(min(index, hits.count - 1) + 1) of \(hits.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
            HStack(spacing: 2) {
                Button { move(-1, in: hits) } label: { Image(systemName: "chevron.up") }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button { move(1, in: hits) } label: { Image(systemName: "chevron.down") }
                    .keyboardShortcut("g", modifiers: .command)
            }
            .buttonStyle(.borderless)
            .disabled(hits.isEmpty)
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackground(in: Capsule())
        .onAppear { focused = true }
        .onChange(of: model.query) { _, _ in
            index = 0
            if let first = TranscriptSearch.hits(in: transcript, query: model.query).first {
                model.focus = (transcript.id, first.start, UUID())
            }
        }
    }

    private func move(_ step: Int, in hits: [TranscriptSearch.Hit]) {
        guard !hits.isEmpty else { return }
        index = (index + step + hits.count) % hits.count
        model.focus = (transcript.id, hits[index].start, UUID())
    }
}
