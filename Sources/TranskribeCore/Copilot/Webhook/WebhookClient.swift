import Foundation

public struct WebhookClient: Sendable {
    public enum DeliveryResult: Equatable, Sendable {
        case sent
        case disabled
        case failed
        case httpError(Int)
        case timedOut
        case missingKey
        case invalidURL

        public var message: String {
            switch self {
            case .sent: return "The webhook event was sent."
            case .disabled: return "The webhook is off."
            case .failed: return "The webhook request failed."
            case .httpError(let status): return "The webhook returned HTTP \(status)."
            case .timedOut: return "The webhook request exceeded 10 seconds."
            case .missingKey: return "Add a webhook key in Settings."
            case .invalidURL: return "Enter an HTTP or HTTPS webhook URL without credentials or a fragment."
            }
        }
    }

    public static let keychainAccount = "copilot-webhook-key"
    private static let defaultSession = makeSession()
    private let session: URLSession
    private let apiKey: @Sendable () -> String?
    private let log: @Sendable (String) -> Void

    public init(session: URLSession? = nil,
                apiKey: @escaping @Sendable () -> String? = {
                    KeychainStore().get(account: WebhookClient.keychainAccount)
                }, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.session = session ?? Self.defaultSession
        self.apiKey = apiKey
        self.log = log
    }

    public func send(_ event: WebhookEvent, to endpoint: URL?) async -> DeliveryResult {
        guard let endpoint else { return .disabled }
        guard Self.endpoint(from: endpoint.absoluteString) != nil else { return report(.invalidURL) }
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return report(.missingKey) }
        do {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try event.encoded()
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return report(.failed) }
            guard (200..<300).contains(response.statusCode) else { return report(.httpError(response.statusCode)) }
            return .sent
        } catch let error as URLError where error.code == .timedOut {
            return report(.timedOut)
        } catch {
            return report(.failed)
        }
    }

    public static func endpoint(from text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }

    private func report(_ result: DeliveryResult) -> DeliveryResult {
        log(result.message)
        return result
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
