import Foundation
import Testing
@testable import TranskribeCore

// This fixture follows the OpenRouter chat-completion stream format.
private let recordedOpenRouterResponse = """
: OPENROUTER PROCESSING

data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

data: {"choices":[{"index":0,"delta":{"content":"Merhaba"}}]}

data: {"choices":[{"index":0,"delta":{"content":" ğüşİ 🌍"}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"choices":[],"usage":{"total_tokens":12}}

data: [DONE]

data: {"choices":[{"index":0,"delta":{"content":"Must not appear"}}]}

"""

@Suite(.serialized) struct OpenRouterProviderTests {
    @Test func availabilityRequiresANonemptyKey() async {
        #expect(await OpenRouterProvider(apiKey: { nil }).availability()
            == .unavailable(reason: "Add an OpenRouter API key in Settings."))
        #expect(await OpenRouterProvider(apiKey: { " \n " }).availability()
            == .unavailable(reason: "Add an OpenRouter API key in Settings."))
        #expect(await OpenRouterProvider(apiKey: { "test-key" }).availability() == .available)
    }
    @Test(arguments: [OpenRouterProvider.grok, OpenRouterProvider.haiku, OpenRouterProvider.luna])
    func streamsTextAndSendsChatMessages(model: AIModel) async throws {
        let key = "openrouter-private-test-key"
        let session = mockSession { request in
            #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
            #expect(request.allHTTPHeaderFields?.filter { $0.value.contains(key) }.count == 1)
            let data = try requestBody(request)
            #expect(!String(decoding: data, as: UTF8.self).contains(key))
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["model"] as? String == model.id)
            #expect(body["stream"] as? Bool == true)
            #expect(body["reasoning"] as? [String: String] == ["effort": "none"])
            #expect(body["messages"] as? [[String: String]] == [
                ["role": "system", "content": "Meeting context"],
                ["role": "user", "content": "Question one"],
                ["role": "assistant", "content": "Earlier answer"],
                ["role": "user", "content": "Question two"],
            ])
            return (200, recordedOpenRouterResponse)
        }
        defer { session.invalidateAndCancel() }
        let provider = OpenRouterProvider(session: session, apiKey: { " \(key)\n" })
        var deltas: [String] = []
        for try await delta in provider.stream(model: model, system: "Meeting context", messages: [
            AIMessage(role: .user, text: "Question one"),
            AIMessage(role: .assistant, text: "Earlier answer"),
            AIMessage(role: .user, text: "Question two"),
        ]) {
            deltas.append(delta)
        }
        #expect(deltas == ["Merhaba", " ğüşİ 🌍"])
    }

    @Test(arguments: [
        (400, "OpenRouter rejected the request. Check the model and transcript length."),
        (401, "OpenRouter rejected your API key. Check it in Settings."),
        (402, "Your OpenRouter credits are insufficient. Add credits to your account."),
        (403, "Your OpenRouter API key cannot use this model."),
        (404, "This model is unavailable through OpenRouter."),
        (429, "You reached the OpenRouter rate limit. Wait a minute and try again."),
        (503, "OpenRouter has a server error. Try again later."),
        (418, "OpenRouter returned an HTTP error (418)."),
    ])
    func mapsHTTPErrorBodiesWithoutExposingServerContent(status: Int, message: String) async {
        let session = mockSession { _ in
            (status, #"{"error":{"code":401,"message":"openrouter-private-test-key secret transcript"}}"#)
        }
        defer { session.invalidateAndCancel() }
        let provider = OpenRouterProvider(session: session, apiKey: { "openrouter-private-test-key" })
        await #expect(throws: AIError(message)) {
            for try await _ in provider.stream(model: OpenRouterProvider.grok, system: "", messages: []) {}
        }
    }

    @Test(arguments: [
        (#"data: {"error":{"code":429,"message":"secret transcript"},"choices":[{"delta":{},"finish_reason":"error"}]}"#,
         "You reached the OpenRouter rate limit. Wait a minute and try again."),
        (#"data: {"error":{"code":402,"message":"secret transcript"}}"#,
         "Your OpenRouter credits are insufficient. Add credits to your account."),
        (#"data: {"error":{"message":"secret transcript"},"choices":[]}"#,
         "OpenRouter could not complete the answer. Try again."),
        (#"data: {"choices":[{"delta":{},"finish_reason":"error"}]}"#,
         "OpenRouter could not complete the answer. Try again."),
        (#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#,
         "OpenRouter stopped before the answer was complete. Try a shorter question."),
        (#"data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#,
         "The OpenRouter model declined to answer this request."),
        (#"data: {"choices":[{"delta":{"content":"Partial"}}]}"#,
         "The OpenRouter stream ended before the answer was complete. Try again."),
        ("data: not-json", "OpenRouter returned an invalid stream event."),
    ])
    func rejectsFailedOrIncompleteStreams(event: String, message: String) async {
        let session = mockSession { _ in (200, event + "\n\n") }
        defer { session.invalidateAndCancel() }
        let provider = OpenRouterProvider(session: session, apiKey: { "test-key" })
        await #expect(throws: AIError(message)) {
            for try await _ in provider.stream(model: OpenRouterProvider.grok, system: "", messages: []) {}
        }
    }

    @Test(arguments: [URLError.Code.cancelled, .timedOut, .notConnectedToInternet])
    func mapsNetworkErrorsAndPreservesCancellation(code: URLError.Code) async {
        let session = mockSession { _ in throw URLError(code) }
        defer { session.invalidateAndCancel() }
        let provider = OpenRouterProvider(session: session, apiKey: { "test-key" })
        if code == .cancelled {
            await #expect(throws: CancellationError.self) {
                for try await _ in provider.stream(model: OpenRouterProvider.grok, system: "", messages: []) {}
            }
        } else {
            await #expect(throws: AIError("Cannot reach OpenRouter. Check your connection and try again.")) {
                for try await _ in provider.stream(model: OpenRouterProvider.grok, system: "", messages: []) {}
            }
        }
    }

    @Test(arguments: [false, true])
    func stopsOpenRequestAfterDoneOrConsumerCancellation(cancelConsumer: Bool) async throws {
        let first = AsyncStream<String>.makeStream()
        let stopped = AsyncStream<Bool>.makeStream()
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"First take\"}}]}\n\n"
            + (cancelConsumer ? "" : "data: [DONE]\n\n")
        let session = mockSession { _ in (200, body) }
        OpenRouterURLProtocol.completesResponse = false
        OpenRouterURLProtocol.onStop = { stopped.continuation.yield(true) }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                first.continuation.yield("Timed out")
                stopped.continuation.yield(false)
                session.invalidateAndCancel()
            }
        }
        defer {
            timeout.cancel()
            session.invalidateAndCancel()
            first.continuation.finish()
            stopped.continuation.finish()
        }
        let provider = OpenRouterProvider(session: session, apiKey: { "test-key" })
        let consumer = Task {
            var deltas: [String] = []
            for try await delta in provider.stream(model: OpenRouterProvider.grok, system: "", messages: []) {
                deltas.append(delta)
                first.continuation.yield(delta)
            }
            return deltas
        }
        #expect(await first.stream.first(where: { _ in true }) == "First take")
        if cancelConsumer { consumer.cancel() }
        do {
            #expect(try await consumer.value == ["First take"])
        } catch is CancellationError {
            #expect(cancelConsumer)
        }
        #expect(await stopped.stream.first(where: { _ in true }) == true)
    }

    @Test func missingKeyNeverSendsARequest() async {
        let session = mockSession { _ in
            Issue.record("The provider sent a request without a key.")
            return (200, recordedOpenRouterResponse)
        }
        defer { session.invalidateAndCancel() }
        let provider = OpenRouterProvider(session: session, apiKey: { nil })
        await #expect(throws: AIError("Add an OpenRouter API key in Settings.")) {
            for try await _ in provider.stream(model: OpenRouterProvider.grok, system: "", messages: []) {}
        }
    }

}

private final class OpenRouterURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    static var completesResponse = true
    static var onStop: (() -> Void)?
    private var stopHandler: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        stopHandler = Self.onStop
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

    override func stopLoading() { stopHandler?() }
}

private func mockSession(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
    OpenRouterURLProtocol.handler = handler
    OpenRouterURLProtocol.completesResponse = true
    OpenRouterURLProtocol.onStop = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OpenRouterURLProtocol.self]
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
