import SwiftUI
import TranskribeCore

struct OpenRouterKeySettings: View {
    @Environment(AIService.self) private var ai
    @State private var key = ""
    @State private var saved = false
    @State private var error: String?
    private let keychain = KeychainStore()

    var body: some View {
        SwiftUI.Section {
            SecureField("sk-or-…", text: $key)
                .accessibilityLabel("OpenRouter API key")
            HStack {
                Button("Save OpenRouter Key", action: saveKey)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove OpenRouter Key", role: .destructive, action: removeKey)
                if saved { Text("Saved to Keychain").foregroundStyle(.secondary) }
            }
            if let error { Text(error).foregroundStyle(.red) }
        } header: {
            Text("OpenRouter API key (optional)")
        } footer: {
            Text("Selecting an OpenRouter model sends transcript text and questions to OpenRouter and the model provider. Transkribe stores the key in Keychain.")
        }
    }

    private func saveKey() {
        do {
            try keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: OpenRouterKeychain.account)
            key = ""
            saved = true
            error = nil
            Task { await ai.refreshAvailability() }
        } catch {
            saved = false
            self.error = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try keychain.delete(account: OpenRouterKeychain.account)
            key = ""
            saved = false
            error = nil
            Task { await ai.refreshAvailability() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
