import Foundation

public struct IntentDefinition: Codable, Equatable, Sendable, Identifiable {
    public enum Speakers: String, Codable, Sendable { case me, anyone }
    public struct Action: Codable, Equatable, Sendable {
        public enum Destination: String, Codable, Sendable { case webhook, ask }
        public let destination: Destination
        public let instruction: String

        public init(destination: Destination, instruction: String) {
            self.destination = destination
            self.instruction = instruction
        }
    }

    public let id: String
    public let description: String
    public let examples: [String]
    public let speakers: Speakers
    public let action: Action
    public let minConfidence: Double
    public let cooldownSec: TimeInterval

    public init(id: String, description: String, examples: [String], speakers: Speakers,
                action: Action, minConfidence: Double, cooldownSec: TimeInterval) {
        self.id = id
        self.description = description
        self.examples = examples
        self.speakers = speakers
        self.action = action
        self.minConfidence = minConfidence
        self.cooldownSec = cooldownSec
    }
}

public struct IntentConfig: Codable, Equatable, Sendable {
    public struct LoadResult: Sendable {
        public let config: IntentConfig
        public let error: String?
    }

    public let version: Int
    public let intents: [IntentDefinition]

    public init(intents: [IntentDefinition] = []) {
        version = 1
        self.intents = intents
    }

    /// A file error disables all intents.
    public static func load(from url: URL) -> LoadResult {
        do {
            let config = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            try config.validate()
            return LoadResult(config: config, error: nil)
        } catch {
            return LoadResult(config: Self(), error: "Transkribe cannot load intents.json: \(error.localizedDescription)")
        }
    }

    private func validate() throws {
        guard version == 1 else { throw AIError("The intents.json version must be 1.") }
        var ids = Set<String>()
        for intent in intents {
            guard !intent.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  intent.id != "none", ids.insert(intent.id).inserted else {
                throw AIError("Each intent must have a unique ID. The ID cannot be empty or none.")
            }
            guard intent.minConfidence.isFinite, (0...1).contains(intent.minConfidence),
                  intent.cooldownSec.isFinite, intent.cooldownSec >= 0 else {
                throw AIError("Intent confidence must be between 0 and 1. The cooldown must be zero or greater.")
            }
            guard !intent.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !intent.action.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIError("Each intent must have a description and an action instruction.")
            }
        }
    }
}
