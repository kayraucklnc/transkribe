import Foundation

public enum DecisionModelSelection: Hashable, Codable, Sendable, Identifiable {
    case haiku
    case openRouter(DecisionModel)

    public static var choices: [Self] { [.haiku] + DecisionModel.curated.map(Self.openRouter) }
    private enum CodingKeys: String, CodingKey { case kind, model }
    private enum Kind: String, Codable { case haiku, openRouter }

    public var id: String {
        switch self {
        case .haiku: "haiku"
        case .openRouter(let model): "openrouter/\(model.id)"
        }
    }

    public var displayName: String {
        switch self {
        case .haiku: AnthropicAPIProvider.haiku.displayName
        case .openRouter(let model): "\(model.displayName) (OpenRouter)"
        }
    }

    public var provider: AIProviderKind {
        switch self {
        case .haiku: .anthropicAPI
        case .openRouter: .openRouter
        }
    }

    public var isSupported: Bool {
        switch self {
        case .haiku: true
        case .openRouter(let model): DecisionModel.curated.contains { $0.id == model.id }
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Earlier versions saved an AIModel without a kind field.
        guard values.contains(.kind) else { self = .haiku; return }
        switch try values.decode(Kind.self, forKey: .kind) {
        case .haiku: self = .haiku
        case .openRouter: self = .openRouter(try values.decode(DecisionModel.self, forKey: .model))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .haiku: try values.encode(Kind.haiku, forKey: .kind)
        case .openRouter(let model):
            try values.encode(Kind.openRouter, forKey: .kind)
            try values.encode(model, forKey: .model)
        }
    }

    /// Returns the selected Haiku provider. Decision models use DecisionClient.
    public static func provider(for selection: Self, providers: [any AIProvider],
                                availability: [AIProviderKind: AIAvailability]) -> (any AIProvider)? {
        guard selection == .haiku, availability[.anthropicAPI]?.isAvailable == true else { return nil }
        return providers.first { provider in
            provider.kind == .anthropicAPI && provider.models.contains { $0.id == AnthropicAPIProvider.haiku.id }
        }
    }
}
