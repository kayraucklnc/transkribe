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
        let response = try JSONDecoder().decode(Response.self, from: data)
        for (id, answer) in response.answers {
            if answer.type == .choice {
                guard let choice = answer.choice, questions[id]?.criteria[choice] != nil else {
                    throw AIError("OpenRouter returned an unknown decision choice.")
                }
            }
        }
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
}
