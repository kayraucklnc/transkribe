import Foundation

/// Maps one HTTP request to one MCP response without opening a network listener.
public struct MCPHTTPHandler {
    public struct Request {
        public let method: String
        public let path: String
        public let headers: [String: String]
        public let body: Data

        public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
            self.method = method
            self.path = path
            self.headers = headers
            self.body = body
        }
    }

    public struct Response {
        public let statusCode: Int
        public let headers: [String: String]
        public let body: Data
    }

    public static let maximumBodyBytes = 1_048_576

    private let server: MCPServer
    private let bearerToken: [UInt8]
    private let allowedOrigins: Set<String>

    public init(server: MCPServer, bearerToken: String, allowedOrigins: Set<String> = []) {
        self.server = server
        self.bearerToken = Array(bearerToken.utf8)
        self.allowedOrigins = allowedOrigins
    }

    public func handle(_ request: Request) -> Response {
        guard isAuthorized(request) else {
            return Response(statusCode: 401, headers: ["WWW-Authenticate": "Bearer"], body: Data())
        }
        let origins = headerValues("origin", in: request)
        guard origins.isEmpty || (origins.count == 1 && allowedOrigins.contains(origins[0])) else {
            return Response(statusCode: 403, headers: [:], body: Data())
        }
        guard request.path == "/mcp" else {
            return Response(statusCode: 404, headers: [:], body: Data())
        }
        guard request.method == "POST" else {
            return Response(statusCode: 405, headers: ["Allow": "POST"], body: Data())
        }
        guard request.body.count <= Self.maximumBodyBytes else {
            return Response(statusCode: 413, headers: [:], body: Data())
        }
        guard let line = String(data: request.body, encoding: .utf8) else {
            return Response(statusCode: 400, headers: [:], body: Data())
        }
        guard let reply = server.handle(line: line) else {
            return Response(statusCode: 202, headers: [:], body: Data())
        }
        return Response(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(reply.utf8))
    }

    private func isAuthorized(_ request: Request) -> Bool {
        let values = headerValues("authorization", in: request)
        guard values.count == 1 else { return false }
        let parts = values[0].split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return tokenMatches(Array(parts[1].utf8))
    }

    private func headerValues(_ name: String, in request: Request) -> [String] {
        request.headers.compactMap { $0.key.lowercased() == name ? $0.value : nil }
    }

    private func tokenMatches(_ candidate: [UInt8]) -> Bool {
        // Compare every configured token byte. Never stop at the first differing byte.
        var difference = candidate.count ^ bearerToken.count
        for index in bearerToken.indices {
            let byte = index < candidate.count ? candidate[index] : 0
            difference |= Int(byte ^ bearerToken[index])
        }
        return difference == 0
    }
}
