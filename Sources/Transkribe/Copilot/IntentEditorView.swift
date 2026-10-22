import SwiftUI
import TranskribeCore

private struct IntentDraft: Identifiable, Equatable {
    var id = UUID()
    var intentID: String
    var description: String
    var examples: String
    var speakers: IntentDefinition.Speakers
    var destination: IntentDefinition.Action.Destination
    var instruction: String
    var minConfidence: String
    var cooldownSec: String
    var enabled: Bool
    var expanded = false

    init(_ intent: IntentDefinition) {
        intentID = intent.id
        description = intent.description
        examples = intent.examples.joined(separator: "\n")
        speakers = intent.speakers
        destination = intent.action.destination
        instruction = intent.action.instruction
        minConfidence = String(intent.minConfidence)
        cooldownSec = String(intent.cooldownSec)
        enabled = intent.enabled
    }

    func definition() throws -> IntentDefinition {
        guard let confidence = Double(minConfidence), let cooldown = Double(cooldownSec) else {
            throw AIError("Enter numbers for minimum confidence and cooldown.")
        }
        return IntentDefinition(id: intentID, description: description,
            examples: examples.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            speakers: speakers, action: .init(destination: destination, instruction: instruction),
            minConfidence: confidence, cooldownSec: cooldown, enabled: enabled)
    }
}

struct IntentEditorView: View {
    @State private var drafts: [IntentDraft] = []
    @State private var error: String?
    @State private var saved = false
    @State private var loaded = false
    private let url = TranscriptStore.supportDirectory.appendingPathComponent("intents.json")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Intents").font(.headline)
                Spacer()
                Button("Add intent", systemImage: "plus") { addIntent() }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            if drafts.isEmpty {
                Text("No intents configured.").foregroundStyle(.secondary)
                Button("Add the examples") { addExamples() }
            }
            ForEach($drafts) { $draft in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Toggle(draft.intentID.isEmpty ? "New intent" : draft.intentID, isOn: $draft.enabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Spacer()
                        Button(draft.expanded ? "Close" : "Edit") { draft.expanded.toggle() }
                        Menu {
                            Button("Duplicate") { duplicate(draft) }
                            Button("Delete", role: .destructive) { drafts.removeAll { $0.id == draft.id } }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("Actions for \(draft.intentID)")
                    }
                    if draft.expanded {
                        IntentFields(draft: $draft)
                    } else {
                        Text(draft.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Divider()
            }
            HStack {
                Button("Save intents") { save() }
                Button("Reload") { load() }
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Text("Select Save intents to save all changes. Changes apply from the next meeting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if !loaded { load() }
        }
        .onChange(of: drafts) { _, _ in saved = false }
    }

    private func addIntent() {
        var draft = IntentDraft(IntentDefinition(id: "", description: "", examples: [], speakers: .me,
            action: .init(destination: .ask, instruction: ""), minConfidence: 0.85, cooldownSec: 30))
        draft.expanded = true
        drafts.append(draft)
    }

    private func addExamples() {
        do {
            drafts = try IntentConfig.examples().intents.map(IntentDraft.init)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func duplicate(_ original: IntentDraft) {
        var draft = original
        draft.id = UUID()
        let base = original.intentID + "_copy"
        var candidate = base
        var suffix = 2
        while drafts.contains(where: { $0.intentID == candidate }) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        draft.intentID = candidate
        draft.expanded = true
        drafts.append(draft)
    }

    private func save() {
        do {
            let config = IntentConfig(intents: try drafts.map { try $0.definition() })
            try config.save(to: url)
            error = nil
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func load() {
        let result = IntentConfig.load(from: url)
        drafts = result.config.intents.map(IntentDraft.init)
        error = result.error
        saved = false
        loaded = true
    }
}

private struct IntentFields: View {
    @Binding var draft: IntentDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("ID") {
                TextField("ID", text: $draft.intentID).labelsHidden()
            }
            LabeledContent("Description") {
                TextField("Description", text: $draft.description, axis: .vertical).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Examples (one per line)").font(.caption)
                TextEditor(text: $draft.examples)
                    .frame(minHeight: 75)
                    .accessibilityLabel("Examples, one per line")
            }
            Picker("Speakers", selection: $draft.speakers) {
                Text("Me").tag(IntentDefinition.Speakers.me)
                Text("Anyone").tag(IntentDefinition.Speakers.anyone)
            }
            Picker("Destination", selection: $draft.destination) {
                Text("Ask").tag(IntentDefinition.Action.Destination.ask)
                Text("Webhook").tag(IntentDefinition.Action.Destination.webhook)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Instruction").font(.caption)
                TextEditor(text: $draft.instruction)
                    .frame(minHeight: 90)
                    .accessibilityLabel("Instruction")
            }
            LabeledContent("Minimum confidence (0–1)") {
                TextField("Minimum confidence", text: $draft.minConfidence)
                    .labelsHidden()
                    .frame(width: 100)
            }
            LabeledContent("Cooldown (seconds)") {
                TextField("Cooldown", text: $draft.cooldownSec)
                    .labelsHidden()
                    .frame(width: 100)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.leading, 12)
    }
}
