import SwiftUI
import TranskribeCore

struct TopicGraphSettingsSection: View {
    @Environment(AppModel.self) private var model
    private let namingModels = OpenRouterProvider().models

    var body: some View {
        @Bindable var model = model
        SwiftUI.Section {
            Toggle("Enable topic graph", isOn: $model.copilotSettings.topicGraph)
            Group {
                Picker("Decision model", selection: $model.copilotSettings.topicGraphSettings.decisionModelID) {
                    ForEach(DecisionModel.curated) { model in
                        Text(model.displayName).tag(model.id)
                    }
                    if !DecisionModel.curated.contains(where: { $0.id == model.copilotSettings.topicGraphSettings.decisionModelID }) {
                        Text("Unavailable: \(model.copilotSettings.topicGraphSettings.decisionModelID)")
                            .tag(model.copilotSettings.topicGraphSettings.decisionModelID)
                    }
                }
                Picker("Naming model", selection: $model.copilotSettings.topicGraphSettings.namingModelID) {
                    ForEach(namingModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                    if !namingModels.contains(where: { $0.id == model.copilotSettings.topicGraphSettings.namingModelID }) {
                        Text("Unavailable: \(model.copilotSettings.topicGraphSettings.namingModelID)")
                            .tag(model.copilotSettings.topicGraphSettings.namingModelID)
                    }
                }
                Stepper("Refresh names every \(model.copilotSettings.topicGraphSettings.namingRefreshWords) words",
                        value: $model.copilotSettings.topicGraphSettings.namingRefreshWords, in: 1...10_000)
            }
            .disabled(!model.copilotSettings.topicGraph)
        } header: {
            Text("Topic graph")
        } footer: {
            Text("Uses OpenRouter for topic routing and names. Requires an OpenRouter API key. An unavailable model stops the graph.")
        }
    }
}
