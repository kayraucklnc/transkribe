import SwiftUI
import TranskribeCore

struct IntentCard: Identifiable {
    let id: UUID
    let intentID: String
    let title: String
    let request: String
    var status: String
    var answer = ""
}

struct IntentCardsView: View {
    let controller: LiveIntentController

    var body: some View {
        ForEach(controller.cards) { card in
            VStack(alignment: .leading, spacing: 8) {
                Label(card.title, systemImage: "bolt.fill")
                    .font(.callout.weight(.semibold))
                Text(card.request).font(.callout).textSelection(.enabled)
                Text(card.status).font(.caption).foregroundStyle(.secondary)
                if !card.answer.isEmpty {
                    MarkdownView(markdown: card.answer)
                }
                HStack {
                    Button("Mute for this meeting") { controller.mute(card.intentID) }
                        .disabled(controller.mutedIntentIDs.contains(card.intentID))
                    Button("Dismiss") { controller.dismiss(card.id) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.2)))
        }
    }
}
