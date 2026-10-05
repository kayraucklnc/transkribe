import SwiftUI
import TranskribeCore

struct SettingsView: View {
    var body: some View {
        TabView {
            TranscriptionSettingsTab()
                .tabItem { Label("Transcription", systemImage: "waveform") }
            DictationSettingsTab()
                .tabItem { Label("Dictation", systemImage: "mic.badge.plus") }
            CallSettingsTab()
                .tabItem { Label("Calls", systemImage: "phone") }
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

private struct CallSettingsTab: View {
    @Environment(CallMonitor.self) private var calls
    @State private var calendarAllowed = CalendarTitles.isAllowed

    var body: some View {
        @Bindable var calls = calls
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Section(title: "When a call starts") {
                    Toggle(isOn: $calls.offersToRecord) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Offer to record it")
                            Text("When Zoom, Teams, FaceTime, WhatsApp, Slack or a browser call starts using your microphone, a small card asks if you want to record. Nothing is recorded unless you say so.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $calls.stopsWithCall) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Stop recording when the call ends")
                            Text("Only for recordings started from that card.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!calls.offersToRecord)
                }
                Section(title: "Calendar") {
                    Toggle(isOn: Binding(get: { calls.usesCalendar && calendarAllowed }, set: { on in
                        guard on else { calls.usesCalendar = false; return }
                        Task {
                            calendarAllowed = await CalendarTitles.requestAccess()
                            calls.usesCalendar = calendarAllowed
                        }
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Name call recordings after your calendar event")
                            Text("“Weekly sync with Hakan” instead of a date. Your calendar stays on this Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .toggleStyle(.switch)
            .padding(24)
        }
    }
}

private struct DictationSettingsTab: View {
    @Environment(DictationController.self) private var dictation
    @State private var isTrusted = TextInserter.isTrusted

    var body: some View {
        @Bindable var dictation = dictation
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Section(title: "Speak anywhere") {
                    Text("Press the shortcut in any app, talk, then press Return. What you said is typed where your cursor is, or copied if there's nowhere to type.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        ShortcutRecorder(shortcut: $dictation.shortcut,
                                         onBegin: dictation.suspendShortcut, onEnd: dictation.installShortcut)
                    }
                    if !dictation.shortcutIsAvailable {
                        Label("Another app is using this shortcut. Pick a different one.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Try It Now") { dictation.start() }
                }
                Section(title: "Speed") {
                    Picker("Speed", selection: $dictation.speed) {
                        ForEach(DictationSpeed.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(dictation.speed.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(title: "Typing for you") {
                    if isTrusted {
                        Label("Transkribe can type into other apps.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("To type into other apps, Transkribe needs Accessibility access. Without it, your words are copied and you press ⌘V.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Allow Typing…") {
                            TextInserter.requestTrust()
                            NSWorkspace.shared.open(TextInserter.settingsURL)
                        }
                    }
                }
            }
            .padding(24)
        }
        .task {
            // Accessibility is granted in System Settings; notice when the user comes back.
            while !Task.isCancelled {
                isTrusted = TextInserter.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
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
