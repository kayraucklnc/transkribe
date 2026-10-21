import SwiftUI
import TranskribeCore

struct MCPServerSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(MCPServerController.self) private var server
    @State private var port = 7788

    var body: some View {
        @Bindable var model = model
        SwiftUI.Section {
            Toggle("MCP server", isOn: $model.copilotSettings.mcpServer)
            LabeledContent("Port") {
                TextField("7788", value: $port, format: .number.grouping(.never))
                    .frame(width: 80)
                    .onSubmit { applyPort() }
                Button("Apply") { applyPort() }
                    .disabled(port < 1 || port > 65535 || port == Int(model.copilotSettings.mcpPort))
            }
            Stepper("Read history: \(model.copilotSettings.mcpReadScopeDays) days",
                    value: $model.copilotSettings.mcpReadScopeDays, in: 0...3650)
            LabeledContent("Local URL") {
                Text("http://127.0.0.1:\(model.copilotSettings.mcpPort)/mcp")
                    .textSelection(.enabled)
                    .font(.callout.monospaced())
            }
            HStack {
                Button("Generate token") { server.generateToken() }.disabled(server.hasToken)
                Button("Copy token") { server.copyToken() }.disabled(!server.hasToken)
                Button("Rotate token") { server.rotateToken() }.disabled(!server.hasToken)
            }
            Text(server.status).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Agent access")
        } footer: {
            Text("The server is off by default. Agents need the bearer token to read live meetings and recent history. They can post answers to Ask. The token stays in Keychain. Rotation revokes the previous token.")
        }
        .onAppear { port = Int(model.copilotSettings.mcpPort) }
    }

    private func applyPort() {
        guard let port = UInt16(exactly: port), port > 0 else { return }
        model.copilotSettings.mcpPort = port
    }
}
