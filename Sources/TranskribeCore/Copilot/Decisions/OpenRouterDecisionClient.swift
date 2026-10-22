import Foundation

public struct OpenRouterDecisionClient: DecisionClient {
    private struct Request: Encodable {
        let model: String
        let state: String
        let questions: [String: DecisionQuestion]
    }

    private struct Response: Decodable {
        let answers: [String: DecisionAnswer]
        let usage: DecisionUsage
    }

    private static let endpoint = URL(string: "https://openrouter.ai/api/alpha/decisions")!
    private static let invalidResponse = AIError("OpenRouter returned an invalid decision response.")
    private let session: URLSession
    private let apiKey: @Sendable () -> String?
    private let onUsage: @Sendable (DecisionUsage) -> Void

    /// Reports usage once per successful request, across all questions.
    public init(session: URLSession = .shared, apiKey: (@Sendable () -> String?)? = nil,
                onUsage: @escaping @Sendable (DecisionUsage) -> Void = { _ in }) {
        self.session = session
        self.apiKey = apiKey ?? { KeychainStore().get(account: OpenRouterKeychain.account) }
        self.onUsage = onUsage
    }

    public func decide(model: DecisionModel, state: String,
                       questions: [String: DecisionQuestion]) async throws -> [String: DecisionAnswer] {
        try Task.checkCancellation()
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
        let (data, httpResponse) = try await send(request)
        try Task.checkCancellation()
        let status = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError(Self.httpError(status: status)) }
        let response = try Self.decode(data, questions: questions)
        try Task.checkCancellation()
        onUsage(response.usage)
        return response.answers
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            if error.code == .timedOut {
                throw AIError("OpenRouter took too long to decide. Try again.")
            }
            throw AIError("Cannot reach OpenRouter. Check your connection and try again.")
        }
    }

    private static func httpError(status: Int) -> String {
        switch status {
        case 401: "OpenRouter rejected your API key. Check it in Settings."
        case 402: "Your OpenRouter credits are exhausted. Add credits to your OpenRouter account."
        case 429: "You reached the OpenRouter rate limit. Wait a minute and try again."
        case 500...599: "OpenRouter has a server error. Try again later."
        default: "OpenRouter returned an HTTP error (\(status))."
        }
    }

    private static func decode(_ data: Data, questions: [String: DecisionQuestion]) throws -> Response {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // Decoder errors can contain response data. Show a fixed message.
            throw invalidResponse
        }
        guard Set(response.answers.keys) == Set(questions.keys),
              response.usage.inputTokens >= 0, response.usage.outputTokens >= 0,
              response.usage.cost.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw invalidResponse }
        for (id, answer) in response.answers {
            guard let question = questions[id], answer.type == question.type else { throw invalidResponse }
            switch answer.type {
            case .choice:
                guard let choice = answer.choice else { throw invalidResponse }
                guard question.criteria[choice] != nil else {
                    throw AIError("OpenRouter returned an unknown decision choice.")
                }
                if let confidence = answer.confidence, !isProbability(confidence) { throw invalidResponse }
                if let probabilities = answer.probabilities {
                    guard Set(probabilities.keys).isSubset(of: Set(question.criteria.keys)),
                          probabilities.values.allSatisfy(isProbability) else { throw invalidResponse }
                }
            case .noul:
                guard let probability = answer.noul, isProbability(probability) else { throw invalidResponse }
            }
        }
        return response
    }

    private static func isProbability(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }
}
