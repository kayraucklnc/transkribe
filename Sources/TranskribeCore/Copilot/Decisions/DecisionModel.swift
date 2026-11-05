import Foundation

public struct DecisionModel: Hashable, Codable, Sendable, Identifiable {
    // Verified with the OpenRouter decisions model catalog on 2026-10-22.
    public static let jev = DecisionModel(id: "~typesafe/jev-latest", displayName: "Jev Latest")
    public static let luna = DecisionModel(id: "openai/gpt-6-luna-decisions", displayName: "GPT-6 Luna Decisions")
    public static let curated: [DecisionModel] = [.jev, .luna]

    public let id: String
    public let displayName: String

    /// Conservative byte limits remain below the catalog context lengths, in tokens.
    public var intentInputByteBudget: Int {
        switch id {
        case Self.jev.id: 200_000
        case Self.luna.id: 500_000
        default: 0
        }
    }

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
