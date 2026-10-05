import EventKit
import SwiftUI
import TranskribeCore

/// Who promised what, with checkboxes, jump-to-moment, and one click into Reminders.
struct ActionItemsTab: View {
    let transcript: Transcript
    @Environment(AIService.self) private var ai
    @Environment(AppModel.self) private var model
    @Environment(PlayerController.self) private var player

    var body: some View {
        let search = ai.actionSearches[transcript.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let items = transcript.actionItems, search == nil {
                    if items.isEmpty {
                        Text("No to-dos in this conversation.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    } else {
                        ForEach(items) { item in
                            ItemRow(item: item, toggle: { toggle(item) }, play: item.time.map { time in { player.play(from: time) } })
                        }
                        HStack {
                            Button {
                                Task { await addToReminders(items.filter { !$0.isDone }) }
                            } label: {
                                Label("Add to Reminders", systemImage: "checklist")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.record)
                            Button("Copy") { copy(items) }
                            Spacer()
                            Button("Look Again") { ai.findActionItems(in: transcript) }
                                .buttonStyle(.borderless)
                        }
                        .padding(.top, 8)
                    }
                } else {
                    Finder(isSearching: search != nil && search! == nil, error: search ?? nil) {
                        ai.findActionItems(in: transcript)
                    }
                }
            }
            .padding(16)
        }
    }

    private func toggle(_ item: ActionItem) {
        model.update(transcript.id, persist: true) { transcript in
            guard let index = transcript.actionItems?.firstIndex(where: { $0.id == item.id }) else { return }
            transcript.actionItems?[index].isDone.toggle()
        }
    }

    private func copy(_ items: [ActionItem]) {
        let text = items.map { item in
            "- [\(item.isDone ? "x" : " ")] \(item.task)" + (item.owner.map { " — \($0)" } ?? "") + (item.due.map { " (\($0))" } ?? "")
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.showToast("To-dos copied")
    }

    private func addToReminders(_ items: [ActionItem]) async {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true, let calendar = store.defaultCalendarForNewReminders() else {
            model.showToast("Allow Reminders in System Settings → Privacy & Security")
            return
        }
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = item.task
            reminder.notes = [item.owner.map { "Owner: \($0)" }, item.due.map { "Due: \($0)" }, "From “\(transcript.title)” in Transkribe"]
                .compactMap { $0 }.joined(separator: "\n")
            try? store.save(reminder, commit: false)
        }
        try? store.commit()
        model.showToast("Added \(items.count) to Reminders")
    }
}

private struct ItemRow: View {
    let item: ActionItem
    let toggle: () -> Void
    let play: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.task)
                    .font(.system(size: 14))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let owner = item.owner { Label(owner, systemImage: "person").labelStyle(.titleAndIcon) }
                    if let due = item.due { Label(due, systemImage: "calendar") }
                    if let play, let time = item.time {
                        Button(action: play) { Label(TranscriptFormatter.timestamp(time), systemImage: "play.fill") }
                            .buttonStyle(.plain)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.3), value: item.isDone)
    }
}

private struct Finder: View {
    let isSearching: Bool
    let error: String?
    let find: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Who's doing what next?")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Finds the commitments and next steps in this conversation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
            if isSearching {
                ProgressView().controlSize(.small)
            } else {
                Button("Find To-dos", action: find)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.record)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
