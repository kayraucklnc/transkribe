import Foundation

public struct CopilotSettings: Codable, Equatable, Sendable {
    public var fastLiveWindow: Bool

    public static let `default` = CopilotSettings()
    private static let key = "copilotSettings"

    private enum CodingKeys: String, CodingKey {
        case fastLiveWindow
    }

    public init(fastLiveWindow: Bool = false) {
        self.fastLiveWindow = fastLiveWindow
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fastLiveWindow = try values.decodeIfPresent(Bool.self, forKey: .fastLiveWindow) ?? false
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
}
