import AppKit
import Observation
import Security
import TranskribeCore

@MainActor
@Observable
final class MCPServerController {
    static let tokenAccount = "mcp-server-token"
    private(set) var status = "Off"
    private(set) var hasToken = false
    private weak var model: AppModel?
    private var listener: MCPHTTPListener?
    private var handler: MCPHTTPHandler?
    private let keychain: KeychainStore
    private var tools: MCPLiveTools?

    init(model: AppModel, keychain: KeychainStore = KeychainStore()) {
        self.model = model
        self.keychain = keychain
        hasToken = keychain.get(account: Self.tokenAccount) != nil
        model.copilotSettingsChanged = { [weak self] in self?.configure() }
        configure()
    }

    func configure() {
        listener?.stop()
        listener = nil
        handler = nil
        guard let model, model.copilotSettings.mcpServer else { status = "Off"; return }
        do {
            let token = try existingOrNewToken()
            let settings = model.copilotSettings
            let tools = MCPLiveTools(snapshots: { [weak self] in
                MainActor.assumeIsolated { self?.snapshots() ?? [] }
            }, readScopeDays: settings.mcpReadScopeDays, answerStore: model.agentAnswerStore)
            self.tools = tools
            model.agentAnswerStore = tools.answerStore
            let server = MCPServer(library: { [weak model] in
                MainActor.assumeIsolated {
                    ConversationLibrary(transcripts: model?.transcripts ?? [], people: model?.people ?? [])
                }
            }, extraTools: tools.tools, scopeFilter: tools.scopeFilter)
            handler = MCPHTTPHandler(server: server, bearerToken: token,
                allowedOrigins: ["http://127.0.0.1:\(settings.mcpPort)", "http://localhost:\(settings.mcpPort)"])
            let listener = try MCPHTTPListener(port: settings.mcpPort, handle: { [weak self] request in
                await self?.respond(to: request)
            }, onFailure: { [weak self] message in
                Task { @MainActor in self?.status = "Server error: \(message)" }
            })
            self.listener = listener
            status = "Listening on 127.0.0.1"
            listener.start()
        } catch {
            status = error.localizedDescription
        }
    }

    func generateToken() {
        do {
            _ = try existingOrNewToken()
            configure()
        } catch { status = error.localizedDescription }
    }

    func rotateToken() {
        do {
            try keychain.set(Self.newToken(), account: Self.tokenAccount)
            hasToken = true
            configure()
        } catch { status = error.localizedDescription }
    }

    func copyToken() {
        guard let token = keychain.get(account: Self.tokenAccount) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }

    private func respond(to request: MCPHTTPHandler.Request) -> MCPHTTPHandler.Response? {
        guard model?.copilotSettings.mcpServer == true else { return nil }
        let response = handler?.handle(request)
        synchronizeAnswers()
        return response
    }

    private func snapshots() -> [MCPConversationSnapshot] {
        guard let model else { return [] }
        return model.transcripts.map { transcript in
            MCPConversationSnapshot(transcript: transcript, isLive: model.liveRecordingID == transcript.id && transcript.recordingEndedAt == nil,
                endedAt: transcript.recordingEndedAt)
        }
    }

    private func synchronizeAnswers() {
        guard let model, let tools else { return }
        for transcript in model.transcripts {
            let answers = tools.answerStore.answers(for: transcript.id)
            guard !answers.isEmpty else { continue }
            var chat = transcript.chat ?? AIChat()
            for answer in answers {
                let message = answer.chatMessage
                if let index = chat.messages.firstIndex(where: { $0.answerId == answer.id }) {
                    chat.messages[index] = message
                } else {
                    chat.messages.append(message)
                }
            }
            if chat != transcript.chat { model.update(transcript.id, persist: true) { $0.chat = chat } }
        }
    }

    private func existingOrNewToken() throws -> String {
        if let token = keychain.get(account: Self.tokenAccount), !token.isEmpty { return token }
        let token = try Self.newToken()
        try keychain.set(token, account: Self.tokenAccount)
        hasToken = true
        return token
    }

    private static func newToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { throw AIError("The system could not generate a secure MCP token.") }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
