import Foundation
import Testing
@testable import TranskribeCore

@Suite struct MCPHTTPHandlerTests {
    private let handler = MCPHTTPHandler(
        server: MCPServer(library: { ConversationLibrary(transcripts: [], people: []) }),
        bearerToken: "test-secret",
        allowedOrigins: ["https://trusted.example"]
    )

    @Test func postReturnsJSONRPCReply() throws {
        let response = handler.handle(.init(
            method: "POST", path: "/mcp",
            headers: ["Authorization": "Bearer test-secret"],
            body: Data(#"{"jsonrpc":"2.0","id":42,"method":"ping"}"#.utf8)
        ))

        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "application/json")
        let reply = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(reply["jsonrpc"] as? String == "2.0")
        #expect(reply["id"] as? Int == 42)
        #expect((reply["result"] as? [String: Any])?.isEmpty == true)
    }

    @Test func notificationReturnsAcceptedWithoutBody() {
        let response = handler.handle(.init(
            method: "POST", path: "/mcp",
            headers: ["Authorization": "Bearer test-secret"],
            body: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        ))

        #expect(response.statusCode == 202)
        #expect(response.body.isEmpty)
        #expect(response.headers["Content-Type"] == nil)
    }

    @Test(arguments: ["GET", "PUT", "DELETE", "OPTIONS"])
    func unsupportedMethodReturnsMethodNotAllowed(method: String) {
        let response = handler.handle(.init(
            method: method, path: "/mcp",
            headers: ["Authorization": "Bearer test-secret"]
        ))

        #expect(response.statusCode == 405)
        #expect(response.headers["Allow"] == "POST")
        #expect(response.body.isEmpty)
    }

    @Test(arguments: ["/", "/other", "/mcp/", "/MCP"])
    func unknownPathReturnsNotFound(path: String) {
        let response = handler.handle(.init(
            method: "POST", path: path,
            headers: ["Authorization": "Bearer test-secret"],
            body: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        ))

        #expect(response.statusCode == 404)
        #expect(response.body.isEmpty)
    }
}
