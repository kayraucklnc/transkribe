import Foundation

public struct DecisionQuestion: Encodable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case choice
        case noul
    }

    public let type: Kind
    public let instructions: String
    public let criteria: [String: String]

    public init(type: Kind, instructions: String, criteria: [String: String]) {
        self.type = type
        self.instructions = instructions
        self.criteria = criteria
    }
}

public struct DecisionAnswer: Decodable, Equatable, Sendable {
    public let type: DecisionQuestion.Kind
    public let choice: String?
    public let confidence: Double?
    public let probabilities: [String: Double]?
    /// The probability of true for a noul question.
    public let noul: Double?

    public init(type: DecisionQuestion.Kind, choice: String? = nil, confidence: Double? = nil,
                probabilities: [String: Double]? = nil, noul: Double? = nil) {
        self.type = type
        self.choice = choice
        self.confidence = confidence
        self.probabilities = probabilities
        self.noul = noul
    }
}

public struct DecisionUsage: Decodable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cost
    }

    public let inputTokens: Int
    public let outputTokens: Int
    public let cost: Double?

    public init(inputTokens: Int, outputTokens: Int, cost: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cost = cost
    }
}

public protocol DecisionClient: Sendable {
    /// Evaluates transcript data against the supplied questions.
    func decide(model: DecisionModel, state: String,
                questions: [String: DecisionQuestion]) async throws -> [String: DecisionAnswer]
}
