import SwiftUI
import TranskribeCore

struct SettingsView: View {
    var body: some View {
        TabView {
            TranscriptionSettingsTab()
                .tabItem { Label("Transcription", systemImage: "waveform") }
            VocabularySettingsTab()
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 600, height: 560)
    }
}

private struct TranscriptionSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Section(title: "Languages you speak") {
                    LanguagePicker(selection: $model.settings.languages)
                }
                Section(title: "How Transkribe listens") {
                    QualityPicker(quality: $model.settings.quality, languages: model.settings.languages)
                }
                Section(title: "Background improvement") {
                    Toggle(isOn: $model.settings.enhanceWhenIdle) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Make transcripts even better while you're away")
                            Text("When your Mac is idle and plugged in, recent conversations are quietly redone at the highest quality.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(model.settings.quality == .best)
                }
                Button("Show Welcome Tour Again") {
                    model.settings.completedOnboarding = false
                }
                .buttonStyle(.link)
            }
            .padding(24)
        }
    }
}

private struct VocabularySettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            Text("Names and words to recognize")
                .font(.headline)
            Text("People, companies, products and jargon you use. Transkribe listens for them and fixes near-misses.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VocabularyEditor(words: $model.settings.vocabulary)
            Spacer()
        }
        .padding(24)
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
    }
}

private struct AISettingsTab: View {
    @Environment(AIService.self) private var ai
    @State private var apiKey = ""
    @State private var saved = false
    private let keychain = KeychainStore()

    var body: some View {
        @Bindable var ai = ai
        Form {
            SwiftUI.Section("AI model") {
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
            SwiftUI.Section {
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
                Text("Only needed if you don't use Claude Code. Stored in your Keychain.")
            }
        }
        .formStyle(.grouped)
        .task { await ai.refreshAvailability() }
    }
}
