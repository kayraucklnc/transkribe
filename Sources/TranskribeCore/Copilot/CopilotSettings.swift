import Foundation

public struct CopilotSettings: Codable, Equatable, Sendable {
    public var fastLiveWindow: Bool
    public var askWhileLive: Bool
    public var mcpServer: Bool
    public var mcpPort: UInt16
    public var mcpReadScopeDays: Int
    public var webhook: URL?

    public static let `default` = CopilotSettings()
    private static let key = "copilotSettings"

    private enum CodingKeys: String, CodingKey {
        case fastLiveWindow
        case askWhileLive
        case mcpServer
        case mcpPort
        case mcpReadScopeDays
        case webhook
    }

    public init(fastLiveWindow: Bool = false, askWhileLive: Bool = false, mcpServer: Bool = false,
                mcpPort: UInt16 = 7788, mcpReadScopeDays: Int = 7, webhook: URL? = nil) {
        self.fastLiveWindow = fastLiveWindow
        self.askWhileLive = askWhileLive
        self.mcpServer = mcpServer
        self.mcpPort = mcpPort
        self.mcpReadScopeDays = mcpReadScopeDays
        self.webhook = webhook
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fastLiveWindow = try values.decodeIfPresent(Bool.self, forKey: .fastLiveWindow) ?? false
        askWhileLive = try values.decodeIfPresent(Bool.self, forKey: .askWhileLive) ?? false
        mcpServer = try values.decodeIfPresent(Bool.self, forKey: .mcpServer) ?? false
        mcpPort = try values.decodeIfPresent(UInt16.self, forKey: .mcpPort) ?? 7788
        mcpReadScopeDays = try values.decodeIfPresent(Int.self, forKey: .mcpReadScopeDays) ?? 7
        webhook = try values.decodeIfPresent(URL.self, forKey: .webhook)
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
        !isLive || askWhileLive || mcpServer
    }

    public func canAsk(status: TranscriptStatus, isLive: Bool) -> Bool {
        guard !isLive || askWhileLive else { return false }
        return status == .done || (isLive && status == .transcribing)
    }
}
