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

    private let server: MCPServer

    public init(server: MCPServer, bearerToken: String, allowedOrigins: Set<String> = []) {
        self.server = server
    }

    public func handle(_ request: Request) -> Response {
        guard request.path == "/mcp" else {
            return Response(statusCode: 404, headers: [:], body: Data())
        }
        guard request.method == "POST" else {
            return Response(statusCode: 405, headers: ["Allow": "POST"], body: Data())
        }
        guard let reply = server.handle(line: String(decoding: request.body, as: UTF8.self)) else {
            return Response(statusCode: 202, headers: [:], body: Data())
        }
        return Response(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(reply.utf8))
    }
}
