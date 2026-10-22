import Foundation

public struct CopilotSettings: Codable, Equatable, Sendable {
    public var fastLiveWindow: Bool
    public var askWhileLive: Bool
    public var mcpServer: Bool
    public var mcpPort: UInt16
    public var mcpReadScopeDays: Int
    public var webhook: URL?
    public var decisionModel: DecisionModelSelection
    public var intents: Bool

    public static let `default` = CopilotSettings()
    private static let key = "copilotSettings"

    private enum CodingKeys: String, CodingKey {
        case fastLiveWindow
        case askWhileLive
        case mcpServer
        case mcpPort
        case mcpReadScopeDays
        case webhook
        case decisionModel
        case intents
    }

    public init(fastLiveWindow: Bool = false, askWhileLive: Bool = false, mcpServer: Bool = false,
                mcpPort: UInt16 = 7788, mcpReadScopeDays: Int = 7, webhook: URL? = nil,
                decisionModel: DecisionModelSelection = .haiku, intents: Bool = false) {
        self.fastLiveWindow = fastLiveWindow
        self.askWhileLive = askWhileLive
        self.mcpServer = mcpServer
        self.mcpPort = mcpPort
        self.mcpReadScopeDays = mcpReadScopeDays
        self.webhook = webhook
        self.decisionModel = decisionModel
        self.intents = intents
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fastLiveWindow = try values.decodeIfPresent(Bool.self, forKey: .fastLiveWindow) ?? false
        askWhileLive = try values.decodeIfPresent(Bool.self, forKey: .askWhileLive) ?? false
        mcpServer = try values.decodeIfPresent(Bool.self, forKey: .mcpServer) ?? false
        mcpPort = try values.decodeIfPresent(UInt16.self, forKey: .mcpPort) ?? 7788
        mcpReadScopeDays = try values.decodeIfPresent(Int.self, forKey: .mcpReadScopeDays) ?? 7
        webhook = try values.decodeIfPresent(URL.self, forKey: .webhook)
        intents = try values.decodeIfPresent(Bool.self, forKey: .intents) ?? false
        decisionModel = try values.decodeIfPresent(DecisionModelSelection.self, forKey: .decisionModel) ?? .haiku
    }

    public static func load(from defaults: UserDefaults = .standard) -> CopilotSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(CopilotSettings.self, from: data) else { return .default }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    public func windowPlanner(isLive: Bool) -> WindowPlanner {
        guard isLive else { return .file }
        return fastLiveWindow ? .fastLive : .live
    }

    public func showsInsights(isLive: Bool) -> Bool {
        !isLive || askWhileLive || mcpServer || intents
    }

    public func canAsk(status: TranscriptStatus, isLive: Bool) -> Bool {
        guard !isLive || askWhileLive else { return false }
        return status == .done || (isLive && status == .transcribing)
    }
}
