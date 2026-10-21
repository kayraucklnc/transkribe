import Foundation
import Testing
@testable import TranskribeCore

@Suite struct MCPHTTPRequestDecoderTests {
    @Test(arguments: [
        ("POST /mcp HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n", 413),
        ("POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n", 400),
        ("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n{}", 400),
        ("POST /mcp HTTP/1.1\r\nAuthorization: Bearer one\r\nAuthorization: Bearer two\r\n\r\n", 400),
        ("POST /mcp HTTP/1.1\r\nOrigin: http://evil\r\nOrigin: http://localhost\r\n\r\n", 400),
        ("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n{}", 400),
        (String(repeating: "x", count: 16385), 431)
    ])
    func rejectsOversizeAndAmbiguousFraming(_ raw: String, _ expected: Int) {
        guard case .failure(let status) = MCPHTTPRequestDecoder.decode(Data(raw.utf8)) else {
            Issue.record("The decoder must reject unsafe HTTP framing."); return
        }
        #expect(status == expected)
    }

    @Test func acceptsChunkedJSONAndWaitsForItsTerminator() {
        let head = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
        let chunks = "1\r\n{\r\n1\r\n}\r\n0\r\n\r\n"
        guard case .incomplete = MCPHTTPRequestDecoder.decode(Data((head + "1\r\n{").utf8)) else {
            Issue.record("The decoder must wait for the chunk terminator."); return
        }
        guard case .request(let request) = MCPHTTPRequestDecoder.decode(Data((head + chunks).utf8)) else {
            Issue.record("The decoder must accept chunked JSON."); return
        }
        #expect(request.body == Data("{}".utf8))
    }

    @Test func waitsForACompleteBodyAndPreservesAuthorization() throws {
        let head = "POST /mcp HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer secret\r\nContent-Length: 2\r\n\r\n"
        guard case .incomplete = MCPHTTPRequestDecoder.decode(Data((head + "{").utf8)) else {
            Issue.record("The decoder must wait for the complete body."); return
        }
        guard case .request(let request) = MCPHTTPRequestDecoder.decode(Data((head + "{}").utf8)) else {
            Issue.record("The decoder must return a complete request."); return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/mcp")
        #expect(request.headers["authorization"] == "Bearer secret")
        #expect(request.body == Data("{}".utf8))
    }
}
