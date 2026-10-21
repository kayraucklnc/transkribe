import SwiftUI
import TranskribeCore

struct WebhookSettings: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var key = ""
    @State private var hasKey = false
    @State private var isSending = false
    @State private var status: String?
    private let keychain = KeychainStore()

    var body: some View {
        SwiftUI.Section {
            TextField("Webhook URL", text: $url)
                .accessibilityLabel("Webhook URL")
            SecureField("Bearer key", text: $key)
                .accessibilityLabel("Webhook bearer key")
            HStack {
                Button("Save webhook") { save() }
                    .disabled(WebhookClient.endpoint(from: url) == nil || (!hasKey && trimmedKey.isEmpty))
                Button("Disable webhook") {
                    model.copilotSettings.webhook = nil
                    status = "The webhook is off."
                }
                .disabled(model.copilotSettings.webhook == nil)
                Button("Remove key", role: .destructive) { removeKey() }
                    .disabled(!hasKey)
            }
            HStack {
                Button("Send test event") { sendTest() }
                    .disabled(model.copilotSettings.webhook == nil || !hasKey || isSending)
                if isSending { ProgressView().controlSize(.small) }
                Text(model.copilotSettings.webhook == nil ? "Off" : "Enabled")
                    .foregroundStyle(.secondary)
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Agent webhook")
        } footer: {
            Text("Off by default. Saving enables meeting and intent events to this URL. Intent events include the heard request and recent transcript. The key stays in Keychain. The test sends a sample meeting.started event.")
        }
        .onAppear {
            url = model.copilotSettings.webhook?.absoluteString ?? ""
            hasKey = !(keychain.get(account: WebhookClient.keychainAccount) ?? "").isEmpty
        }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard let endpoint = WebhookClient.endpoint(from: url) else {
            status = WebhookClient.DeliveryResult.invalidURL.message
            return
        }
        do {
            if !trimmedKey.isEmpty {
                try keychain.set(trimmedKey, account: WebhookClient.keychainAccount)
                hasKey = true
                key = ""
            }
            guard hasKey else {
                status = WebhookClient.DeliveryResult.missingKey.message
                return
            }
            model.copilotSettings.webhook = endpoint
            url = endpoint.absoluteString
            status = "The webhook is enabled. The key is in Keychain."
        } catch {
            status = "The webhook key could not be saved in Keychain."
        }
    }

    private func removeKey() {
        do {
            try keychain.delete(account: WebhookClient.keychainAccount)
            model.copilotSettings.webhook = nil
            key = ""
            hasKey = false
            status = "The key was removed. The webhook is off."
        } catch {
            status = "The webhook key could not be removed from Keychain."
        }
    }

    private func sendTest() {
        guard let endpoint = model.copilotSettings.webhook, !isSending else { return }
        let event = WebhookEvent(type: .meetingStarted, conversationId: UUID(),
            title: "Transkribe webhook test", startedAt: Date())
        isSending = true
        status = nil
        Task {
            defer { isSending = false }
            status = await WebhookClient().send(event, to: endpoint).message
        }
    }
}
