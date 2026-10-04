import SwiftUI
import TranskribeCore

struct SettingsView: View {
    @Environment(AIService.self) private var ai
    @State private var apiKey = ""
    @State private var saved = false
    private let keychain = KeychainStore()

    var body: some View {
        @Bindable var ai = ai
        Form {
            Section("AI model") {
                Picker("Default model", selection: $ai.selectedModel) {
                    ForEach(ai.allModels) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                ForEach(ai.providers.map(\.kind), id: \.self) { kind in
                    LabeledContent(ModelPicker.title(for: kind)) {
                        switch ai.availability[kind] {
                        case .available?: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .unavailable(let reason)?: Text(reason).foregroundStyle(.secondary)
                        case nil: ProgressView().controlSize(.small)
                        }
                    }
                }
            }
            Section {
                SecureField("sk-ant-…", text: $apiKey)
                HStack {
                    Button("Save Key") {
                        try? keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: AnthropicAPIProvider.keychainAccount)
                        apiKey = ""
                        saved = true
                        Task { await ai.refreshAvailability() }
                    }
                    .disabled(apiKey.isEmpty)
                    Button("Remove Key", role: .destructive) {
                        try? keychain.delete(account: AnthropicAPIProvider.keychainAccount)
                        Task { await ai.refreshAvailability() }
                    }
                    if saved { Text("Saved to Keychain").foregroundStyle(.secondary) }
                }
            } header: {
                Text("Anthropic API key (optional)")
            } footer: {
                Text("Only needed if you don't use Claude Code. Stored in your Keychain. Transcripts are sent to the model you choose; Apple Intelligence keeps everything on this Mac.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
        .task { await ai.refreshAvailability() }
    }
}
