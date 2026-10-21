import Foundation
import Testing
@testable import TranskribeCore

// A Responses API fixture based on the documented event format.
// Tool and final-text events must not repeat deltas.
private let recordedResponse = """
: keep-alive

event: response.created
data: {"type":"response.created","response":{"id":"resp_fixture","status":"in_progress"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"web_search_call","status":"in_progress"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":"Merhaba"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":" ğüşİ 🌍"}

event: response.output_text.done
data: {"type":"response.output_text.done","text":"Merhaba ğüşİ 🌍"}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_fixture","status":"completed"}}

"""

@Suite(.serialized) struct XAIProviderTests {
    @Test func availabilityRequiresANonemptyKey() async {
        #expect(await XAIProvider(apiKey: { nil }).availability()
            == .unavailable(reason: "Add an xAI API key in Settings."))
        #expect(await XAIProvider(apiKey: { " \n " }).availability()
            == .unavailable(reason: "Add an xAI API key in Settings."))
        #expect(await XAIProvider(apiKey: { "test-key" }).availability() == .available)
    }

    @Test func streamsTextAndSendsTheKeyOnlyInAuthorization() async throws {
        let key = "xai-private-test-key"
        let session = mockSession { request in
            #expect(request.url?.absoluteString == "https://api.x.ai/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
            #expect(request.allHTTPHeaderFields?.filter { $0.value.contains(key) }.count == 1)
            let data = try requestBody(request)
            #expect(!String(decoding: data, as: UTF8.self).contains(key))
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["model"] as? String == "grok-4.3")
            #expect(body["stream"] as? Bool == true)
            #expect(body["store"] as? Bool == false)
            #expect(body["reasoning"] as? [String: String] == ["effort": "none"])
            #expect(body["tools"] as? [[String: String]] == [["type": "web_search"], ["type": "x_search"]])
            #expect(body["input"] as? [[String: String]] == [
                ["role": "system", "content": "Meeting context"],
                ["role": "user", "content": "Question one"],
                ["role": "assistant", "content": "Earlier answer"],
                ["role": "user", "content": "Question two"],
            ])
            return (200, recordedResponse)
        }
        defer { session.invalidateAndCancel() }
        let provider = XAIProvider(session: session, apiKey: { " \(key)\n" })
        var deltas: [String] = []
        for try await delta in provider.stream(model: XAIProvider.grok, system: "Meeting context", messages: [
            AIMessage(role: .user, text: "Question one"),
            AIMessage(role: .assistant, text: "Earlier answer"),
            AIMessage(role: .user, text: "Question two"),
        ]) {
            deltas.append(delta)
        }
        #expect(deltas == ["Merhaba", " ğüşİ 🌍"])
    }

    @Test(arguments: [
        (400, "xAI rejected the request. Check the model and transcript length."),
        (401, "xAI rejected your API key. Check it in Settings."),
        (403, "Your xAI API key cannot use this model."),
        (404, "This model is unavailable with your xAI API key."),
        (413, "This transcript is too long to send to xAI."),
        (429, "You reached the xAI rate limit. Wait a minute and try again."),
        (503, "xAI has a server error. Try again later."),
        (418, "xAI returned an HTTP error (418)."),
    ])
    func mapsHTTPErrorsWithoutExposingServerContent(status: Int, message: String) async {
        let session = mockSession { _ in (status, #"{"error":{"message":"xai-private-test-key secret transcript"}}"#) }
        defer { session.invalidateAndCancel() }
        let provider = XAIProvider(session: session, apiKey: { "xai-private-test-key" })
        await #expect(throws: AIError(message)) {
            for try await _ in provider.stream(model: XAIProvider.grok, system: "", messages: []) {}
        }
    }

    @Test(arguments: [
        (#"data: {"type":"response.failed","response":{"error":{"code":"rate_limit_exceeded","message":"secret"}}}"#,
         "You reached the xAI rate limit. Wait a minute and try again."),
        (#"data: {"type":"error","code":"invalid_api_key","message":"secret"}"#,
         "xAI rejected your API key. Check it in Settings."),
        (#"data: {"type":"response.failed","response":{"error":{"code":"server_error","message":"secret"}}}"#,
         "xAI has a server error. Try again later."),
        (#"data: {"type":"response.failed","response":{"error":{"code":"unknown","message":"secret"}}}"#,
         "xAI could not complete the answer. Try again."),
        (#"data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#,
         "xAI stopped before the answer was complete. Try a shorter question."),
        (#"data: {"type":"response.refusal.delta","delta":"No"}"#,
         "Grok declined to answer this request."),
        (#"data: {"type":"response.output_text.delta","delta":"Partial"}"#,
         "The xAI stream ended before the answer was complete. Try again."),
        ("data: not-json", "xAI returned an invalid stream event."),
    ])
    func rejectsFailedOrIncompleteStreams(event: String, message: String) async {
        let session = mockSession { _ in (200, event + "\n\n") }
        defer { session.invalidateAndCancel() }
        let provider = XAIProvider(session: session, apiKey: { "test-key" })
        await #expect(throws: AIError(message)) {
            for try await _ in provider.stream(model: XAIProvider.grok, system: "", messages: []) {}
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut])
    func mapsNetworkErrors(code: URLError.Code) async {
        let session = mockSession { _ in throw URLError(code) }
        defer { session.invalidateAndCancel() }
        let provider = XAIProvider(session: session, apiKey: { "test-key" })
        await #expect(throws: AIError("Cannot reach xAI. Check your connection and try again.")) {
            for try await _ in provider.stream(model: XAIProvider.grok, system: "", messages: []) {}
        }
    }

    @Test func missingKeyNeverSendsARequest() async {
        let session = mockSession { _ in
            Issue.record("The provider sent a request without a key.")
            return (200, recordedResponse)
        }
        defer { session.invalidateAndCancel() }
        let provider = XAIProvider(session: session, apiKey: { nil })
        await #expect(throws: AIError("Add an xAI API key in Settings.")) {
            for try await _ in provider.stream(model: XAIProvider.grok, system: "", messages: []) {}
        }
    }

    @Test func preservesCancellation() async {
        let session = mockSession { _ in throw URLError(.cancelled) }
        defer { session.invalidateAndCancel() }
        let provider = XAIProvider(session: session, apiKey: { "test-key" })
        await #expect(throws: CancellationError.self) {
            for try await _ in provider.stream(model: XAIProvider.grok, system: "", messages: []) {}
        }
    }

    @Test func yieldsTextBeforeTheHTTPResponseFinishes() async throws {
        let session = mockSession { _ in
            (200, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"First take\"}\n\n")
        }
        XAIURLProtocol.completesResponse = false
        let timeout = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { session.invalidateAndCancel() }
        }
        defer {
            timeout.cancel()
            session.invalidateAndCancel()
        }
        let provider = XAIProvider(session: session, apiKey: { "test-key" })
        var firstDelta: String?
        for try await delta in provider.stream(model: XAIProvider.grok, system: "", messages: []) {
            firstDelta = delta
            break
        }
        #expect(firstDelta == "First take")
    }
}

private final class XAIURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    static var completesResponse = true

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": status == 200 ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Split UTF-8 characters and event lines across network chunks.
            for byte in body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
            if Self.completesResponse { client?.urlProtocolDidFinishLoading(self) }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func mockSession(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
    XAIURLProtocol.handler = handler
    XAIURLProtocol.completesResponse = true
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [XAIURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(contentsOf: buffer.prefix(count))
    }
    return body
}
