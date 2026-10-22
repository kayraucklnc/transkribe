import SwiftUI
import TranskribeCore

struct DecisionModelSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(AIService.self) private var ai

    var body: some View {
        @Bindable var model = model
        SwiftUI.Section {
            Toggle("Spoken intents", isOn: $model.copilotSettings.intents)
            Picker("Decision model", selection: $model.copilotSettings.decisionModel) {
                ForEach(ai.allModels) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            if let notice = ai.decisionModelNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            IntentEditorView()
        } header: {
            Text("Background work")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Intent actions can send speech to the Ask model or webhook.")
                Text("This model is separate from the default AI model. Selecting it does not enable background features.")
                if model.copilotSettings.decisionModel.provider != .appleIntelligence {
                    Text("Background work sends transcript text to the selected cloud provider.")
                }
                Text("If this model becomes unavailable, background work stops. Transkribe never selects a replacement model.")
            }
        }
    }
}
