import Foundation

public struct OpenRouterDecisionClient: DecisionClient {
    private struct Request: Encodable {
        let model: String
        let state: String
        let questions: [String: DecisionQuestion]
    }

    private struct Response: Decodable {
        let answers: [String: DecisionAnswer]
    }

    private static let endpoint = URL(string: "https://openrouter.ai/api/alpha/decisions")!
    private let session: URLSession
    private let apiKey: @Sendable () -> String?

    public init(session: URLSession = .shared, apiKey: (@Sendable () -> String?)? = nil) {
        self.session = session
        self.apiKey = apiKey ?? { KeychainStore().get(account: OpenRouterKeychain.account) }
    }

    public func decide(model: DecisionModel, state: String,
                       questions: [String: DecisionQuestion]) async throws -> [String: DecisionAnswer] {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw AIError("Add an OpenRouter API key in Settings.")
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Request(model: model.id, state: state, questions: questions))
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(Response.self, from: data).answers
    }
}
