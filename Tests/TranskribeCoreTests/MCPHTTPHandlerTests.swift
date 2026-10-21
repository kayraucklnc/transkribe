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

    @Test(arguments: [
        [:],
        ["Authorization": "Bearer wrong-token"],
        ["Authorization": "Bearer Test-secret"],
        ["Authorization": "Bearer test-secreT"],
        ["Authorization": "Bearer test-secret-extra"],
        ["Authorization": "Bearer test-secre"],
        ["Authorization": "Basic test-secret"],
        ["Authorization": "test-secret"],
        ["Authorization": "Bearer "],
        ["Authorization": "Bearer test-secret", "authorization": "Bearer test-secret"],
    ])
    func invalidAuthorizationReturnsUnauthorized(headers: [String: String]) {
        let response = handler.handle(.init(
            method: "POST", path: "/mcp", headers: headers,
            body: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        ))

        #expect(response.statusCode == 401)
        #expect(response.headers["WWW-Authenticate"] == "Bearer")
        #expect(response.body.isEmpty)
    }

    @Test(arguments: ["POST", "GET"], [
        ["Origin": "https://evil.example"],
        ["origin": "https://evil.example"],
        ["Origin": "https://trusted.example.evil.example"],
        ["Origin": "http://trusted.example"],
        ["Origin": "null"],
        ["Origin": ""],
        ["Origin": "https://trusted.example", "origin": "https://evil.example"],
    ])
    func untrustedOriginReturnsForbidden(method: String, originHeaders: [String: String]) {
        var headers = originHeaders
        headers["Authorization"] = "Bearer test-secret"
        let response = handler.handle(.init(
            method: method, path: "/mcp", headers: headers,
            body: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        ))

        #expect(response.statusCode == 403)
        #expect(response.body.isEmpty)
    }

    @Test(arguments: [1_048_576, 1_048_577])
    func bodyLimitUsesActualByteCount(byteCount: Int) {
        let message = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        let body = message + Data(repeating: 0x20, count: byteCount - message.count)
        let response = handler.handle(.init(
            method: "POST", path: "/mcp",
            headers: ["Authorization": "Bearer test-secret", "Content-Length": "1"],
            body: body
        ))

        if byteCount == 1_048_576 {
            #expect(response.statusCode == 200)
            #expect(response.headers["Content-Type"] == "application/json")
        } else {
            #expect(response.statusCode == 413)
            #expect(response.body.isEmpty)
        }
    }

    @Test func invalidUTF8ReturnsBadRequest() {
        let response = handler.handle(.init(
            method: "POST", path: "/mcp",
            headers: ["Authorization": "Bearer test-secret"], body: Data([0xFF])
        ))

        #expect(response.statusCode == 400)
        #expect(response.body.isEmpty)
    }

    @Test func allowedOriginAndCaseInsensitiveHeadersPermitToolCalls() throws {
        let transcript = Fixtures.transcript(title: "Caffè meeting")
        let handler = MCPHTTPHandler(
            server: MCPServer(library: { ConversationLibrary(transcripts: [transcript], people: []) }),
            bearerToken: "test-secret", allowedOrigins: ["https://trusted.example"]
        )
        let response = handler.handle(.init(
            method: "POST", path: "/mcp",
            headers: ["aUtHoRiZaTiOn": "bEaReR test-secret", "oRiGiN": "https://trusted.example"],
            body: Data(#"{"jsonrpc":"2.0","id":"tool-1","method":"tools/call","params":{"name":"list_conversations","arguments":{}}}"#.utf8)
        ))

        #expect(response.statusCode == 200)
        let reply = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(reply["id"] as? String == "tool-1")
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect((content.first?["text"] as? String)?.contains("Caffè meeting") == true)
    }

    @Test(arguments: [("not JSON", -32700), (#"{"jsonrpc":"2.0","id":1,"method":"unknown"}"#, -32601)])
    func returnsServerErrorsAsJSON(message: String, code: Int) throws {
        let response = handler.handle(.init(
            method: "POST", path: "/mcp",
            headers: ["Authorization": "Bearer test-secret"], body: Data(message.utf8)
        ))

        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "application/json")
        let reply = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect((reply["error"] as? [String: Any])?["code"] as? Int == code)
    }
}
