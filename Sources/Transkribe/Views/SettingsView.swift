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
                Section(title: "Live transcription") {
                    Toggle("Faster live text (uses more CPU)", isOn: $model.copilotSettings.fastLiveWindow)
                        .toggleStyle(.switch)
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
                            Text("When Zoom, Teams, FaceTime, WhatsApp, Slack or a browser call starts using your microphone, a card by the notch asks if you want to record. Nothing is recorded unless you say so.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $calls.stopsWithCall) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Stop recording when the call ends")
                            Text("Only for recordings started from that card or a reminder. During a calendar meeting, a quiet mic (say, while you're muted) never stops it before the planned end.")
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
                MeetingReminderSettings(calendarAllowed: $calendarAllowed)
                BrowserAccessSettings()
                RecordingStatusSettings()
            }
            .toggleStyle(.switch)
            .padding(24)
        }
    }
}

private struct MeetingReminderSettings: View {
    @Environment(MeetingReminders.self) private var reminders
    @Environment(CallMonitor.self) private var calls
    @Binding var calendarAllowed: Bool
    @State private var customMinutes = ""

    private static let presets = [0, 1, 2, 5, 10, 15, 30, 60]

    var body: some View {
        @Bindable var reminders = reminders
        @Bindable var calls = calls
        Section(title: "Meeting reminders") {
            Toggle(isOn: $reminders.isEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remind me before meetings")
                    Text("A card grows out of the notch with a Join button. Uses the calendars on this Mac: add Google in System Settings › Internet Accounts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if reminders.isEnabled, !calendarAllowed {
                Button("Allow Calendar Access…") {
                    Task { calendarAllowed = await reminders.requestCalendarAccess() }
                }
            }
            if reminders.isEnabled {
                FlowLayout(spacing: 6) {
                    ForEach(reminders.minutes, id: \.self) { minutes in
                        ReminderChip(label: MeetingCountdown.label(minutesBefore: minutes)) {
                            reminders.removeReminder(minutesBefore: minutes)
                        }
                    }
                    Menu {
                        ForEach(Self.presets.filter { !reminders.minutes.contains($0) }, id: \.self) { minutes in
                            Button(MeetingCountdown.label(minutesBefore: minutes)) { reminders.addReminder(minutesBefore: minutes) }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                HStack(spacing: 6) {
                    TextField("Minutes", text: $customMinutes)
                        .frame(width: 70)
                        .onSubmit(addCustom)
                    Text("min before")
                        .foregroundStyle(.secondary)
                    Button("Add", action: addCustom)
                        .disabled(Int(customMinutes).map { !(0...MeetingReminderSchedule.maximumMinutes).contains($0) } ?? true)
                }
                .font(.callout)
                if reminders.minutes.isEmpty {
                    Text("No reminders. Add a time above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(isOn: $reminders.recordsWhenJoining) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Record when I join from a reminder")
                        Text("Recording starts once the call picks up your microphone and stops when you leave the call, even if it runs past the calendar end time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $calls.recordsCalendarMeetings) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Also record calendar meetings I join another way")
                        Text("When a call starts during a meeting on your calendar that has a Meet, Zoom or Teams link, record it without asking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if calendarAllowed {
                    NextMeetingLine(meeting: reminders.next)
                }
            }
        }
        .onAppear { calendarAllowed = reminders.calendarAllowed }
    }

    private func addCustom() {
        guard let minutes = Int(customMinutes.trimmingCharacters(in: .whitespaces)),
              (0...MeetingReminderSchedule.maximumMinutes).contains(minutes) else { return }
        reminders.addReminder(minutesBefore: minutes)
        customMinutes = ""
    }
}

/// Shows the calendar is connected: "Next: Weekly sync, in 40 min · Google Meet".
private struct NextMeetingLine: View {
    let meeting: CalendarMeeting?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let meeting {
                Label {
                    Text("Next: \(meeting.title), \(MeetingCountdown.text(until: meeting.start, now: context.date))")
                        + Text(meeting.link == nil ? " · no call link" : " · has a call link").foregroundStyle(.tertiary)
                } icon: {
                    Image(systemName: "calendar")
                }
            } else {
                Label("No meetings in the next day.", systemImage: "calendar")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct ReminderChip: View {
    let label: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove this reminder")
        }
        .font(.callout)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

/// Which installed browsers Transkribe can see meeting tabs in, with a button for each one that can't yet.
private struct BrowserAccessSettings: View {
    @Environment(PermissionCenter.self) private var permissions
    @State private var access: [String: BrowserTabs.Access] = [:]

    private var installed: [Browser] {
        Browsers.all.filter(BrowserTabs.isInstalled)
    }

    var body: some View {
        Section(title: "Browsers") {
            Text("For calls in a browser, Transkribe looks for the meeting tab so the recording follows the real meeting and gets the right name. Firefox, Zen and similar browsers use Accessibility; the others ask once.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(installed, id: \.bundleID) { browser in
                HStack {
                    Text(browser.name)
                    Spacer()
                    status(for: browser)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                access = Dictionary(uniqueKeysWithValues: installed.map { ($0.bundleID, BrowserTabs.access(to: $0)) })
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder
    private func status(for browser: Browser) -> some View {
        switch access[browser.bundleID] {
        case .allowed?:
            Label(browser.needsAutomation ? "Allowed" : "Allowed (Accessibility)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .denied?:
            Button("Open Settings") { permissions.openSettings(.browser(bundleID: browser.bundleID)) }
        default:
            Button("Allow") {
                Task {
                    await permissions.request(browser.needsAutomation ? .browser(bundleID: browser.bundleID) : .accessibility)
                    access[browser.bundleID] = BrowserTabs.access(to: browser)
                }
            }
        }
    }
}

private struct RecordingStatusSettings: View {
    @Environment(NotchHUD.self) private var hud

    var body: some View {
        @Bindable var hud = hud
        Section(title: "While recording") {
            Toggle(isOn: $hud.showsRecording) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show recording status by the notch")
                    Text("A red dot and timer next to the notch, and a clear moment when recording starts and stops. People you share your screen with don't see it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Play a sound when recording starts and stops", isOn: $hud.playsSounds)
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
    @Environment(AppModel.self) private var model
    @State private var apiKey = ""
    @State private var saved = false
    @State private var xaiKey = ""
    @State private var xaiKeySaved = false
    @State private var xaiKeyError: String?
    private let keychain = KeychainStore()

    var body: some View {
        @Bindable var ai = ai
        @Bindable var model = model
        Form {
            SwiftUI.Section {
                Toggle("Ask while recording", isOn: $model.copilotSettings.askWhileLive)
            } header: {
                Text("Live questions")
            } footer: {
                Text("Answers use the transcript so far and the selected model. This option is off by default.")
            }
            TopicGraphSettingsSection()
            MCPServerSettings()
            WebhookSettings()
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
            SwiftUI.Section {
                SecureField("xai-…", text: $xaiKey)
                    .accessibilityLabel("xAI API key")
                HStack {
                    Button("Save xAI Key") {
                        do {
                            try keychain.set(xaiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: XAIProvider.keychainAccount)
                            xaiKey = ""
                            xaiKeySaved = true
                            xaiKeyError = nil
                            Task { await ai.refreshAvailability() }
                        } catch {
                            xaiKeySaved = false
                            xaiKeyError = error.localizedDescription
                        }
                    }
                    .disabled(xaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove xAI Key", role: .destructive) {
                        do {
                            try keychain.delete(account: XAIProvider.keychainAccount)
                            xaiKey = ""
                            xaiKeySaved = false
                            xaiKeyError = nil
                            Task { await ai.refreshAvailability() }
                        } catch {
                            xaiKeyError = error.localizedDescription
                        }
                    }
                    if xaiKeySaved { Text("Saved to Keychain").foregroundStyle(.secondary) }
                }
                if let xaiKeyError { Text(xaiKeyError).foregroundStyle(.red) }
            } header: {
                Text("xAI API key (optional)")
            } footer: {
                Text("Selecting Grok sends the transcript and questions to xAI. Grok can search the web and X. Transkribe stores the key in Keychain.")
            }
            OpenRouterKeySettings()
        }
        .formStyle(.grouped)
        .task { await ai.refreshAvailability() }
    }
}
