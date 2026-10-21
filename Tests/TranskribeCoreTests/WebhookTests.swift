import Foundation
import Testing
@testable import TranskribeCore

@Suite(.serialized) struct WebhookTests {
    private let eventId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let conversationId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let startedAt = Date(timeIntervalSince1970: 0)

    @Test(arguments: ["meeting.started", "meeting.ended"])
    func meetingPayloadIsStable(type: String) throws {
        let event = WebhookEvent(type: try #require(WebhookEvent.EventType(rawValue: type)),
            eventId: eventId, conversationId: conversationId, title: "Weekly sync", startedAt: startedAt)
        let expected = """
        {"conversationId":"22222222-2222-2222-2222-222222222222","eventId":"11111111-1111-1111-1111-111111111111","startedAt":"1970-01-01T00:00:00Z","title":"Weekly sync","type":"\(type)","version":1}
        """
        #expect(String(decoding: try event.encoded(), as: UTF8.self) == expected)
        #expect(try event.encoded() == event.encoded())
    }

    @Test func intentPayloadKeepsInstructionSeparateFromHeardData() throws {
        let intent = WebhookEvent.Intent(id: "explicit-ask", instruction: "Research the quoted request.",
            request: "Grok, compare Acme", context: "[00:10] Me: Grok, compare Acme")
        let event = WebhookEvent(type: .intent, eventId: eventId, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt, intent: intent)
        let expected = #"{"conversationId":"22222222-2222-2222-2222-222222222222","eventId":"11111111-1111-1111-1111-111111111111","intent":{"context":"[00:10] Me: Grok, compare Acme","id":"explicit-ask","instruction":"Research the quoted request.","request":"Grok, compare Acme"},"startedAt":"1970-01-01T00:00:00Z","title":"Weekly sync","type":"intent","version":1}"#
        #expect(String(decoding: try event.encoded(), as: UTF8.self) == expected)
    }

    @Test func postsJSONWithBearerKeyAndTenSecondTimeout() async throws {
        let key = "private-webhook-key"
        let event = WebhookEvent(type: .meetingStarted, eventId: eventId, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt)
        let session = webhookSession { request in
            #expect(request.url?.absoluteString == "https://webhook.example/events")
            #expect(request.httpMethod == "POST")
            #expect(request.timeoutInterval == 10)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try webhookBody(request)
            #expect(try body == event.encoded())
            #expect(!String(decoding: body, as: UTF8.self).contains(key))
            return (204, "")
        }
        defer { session.invalidateAndCancel() }
        let client = WebhookClient(session: session, apiKey: { key })
        #expect(await client.send(event, to: URL(string: "https://webhook.example/events")) == .sent)
    }

    @Test func serverFailureDoesNotThrowOrRetryOrLogSecrets() async {
        let key = "private-webhook-key"
        let log = WebhookTestLog()
        let session = webhookSession { request in
            log.append("attempt")
            let body = try webhookBody(request)
            #expect(!String(decoding: body, as: UTF8.self).contains(key))
            return (500, "Server echoed \(key) and confidential transcript")
        }
        defer { session.invalidateAndCancel() }
        let client = WebhookClient(session: session, apiKey: { key }, log: { log.append($0) })
        let event = WebhookEvent(type: .meetingEnded, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt)
        #expect(await client.send(event, to: URL(string: "https://webhook.example/events")) == .httpError(500))
        #expect(log.messages == ["attempt", "The webhook returned HTTP 500."])
        #expect(!log.messages.joined().contains(key))
        #expect(!log.messages.joined().contains("confidential transcript"))
    }

    @Test func timeoutDoesNotThrowOrRetryOrLogTheUnderlyingError() async {
        let log = WebhookTestLog()
        let key = "private-webhook-key"
        let session = webhookSession { request in
            log.append("attempt")
            #expect(request.timeoutInterval == 10)
            throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "Timed out: \(key)"])
        }
        defer { session.invalidateAndCancel() }
        let client = WebhookClient(session: session, apiKey: { key }, log: { log.append($0) })
        let event = WebhookEvent(type: .meetingEnded, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt)
        #expect(await client.send(event, to: URL(string: "https://webhook.example/events")) == .timedOut)
        #expect(log.messages == ["attempt", "The webhook request exceeded 10 seconds."])
        #expect(!log.messages.joined().contains(key))
    }

    @Test func disabledWebhookDoesNotReadKeyOrSendOrLog() async {
        let log = WebhookTestLog()
        let session = webhookSession { _ in
            Issue.record("A disabled webhook sent a request.")
            return (204, "")
        }
        defer { session.invalidateAndCancel() }
        let client = WebhookClient(session: session, apiKey: {
            Issue.record("A disabled webhook read the key.")
            return "private-key"
        }, log: { log.append($0) })
        let event = WebhookEvent(type: .meetingStarted, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt)
        #expect(await client.send(event, to: nil) == .disabled)
        #expect(log.messages.isEmpty)
    }

    @Test(arguments: [nil, "", " \n "] as [String?])
    func missingKeyDoesNotSend(key: String?) async {
        let session = webhookSession { _ in
            Issue.record("A webhook without a key sent a request.")
            return (204, "")
        }
        defer { session.invalidateAndCancel() }
        let client = WebhookClient(session: session, apiKey: { key })
        let event = WebhookEvent(type: .meetingStarted, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt)
        #expect(await client.send(event, to: URL(string: "https://webhook.example/events")) == .missingKey)
    }

    @Test(arguments: ["file:///tmp/events", "ftp://webhook.example", "https://user:secret@webhook.example/events", "https://webhook.example/#secret"])
    func rejectsInvalidEndpointsBeforeReadingTheKey(endpoint: String) async {
        #expect(WebhookClient.endpoint(from: endpoint) == nil)
        let session = webhookSession { _ in
            Issue.record("An invalid webhook URL received a request.")
            return (204, "")
        }
        defer { session.invalidateAndCancel() }
        let client = WebhookClient(session: session, apiKey: {
            Issue.record("An invalid webhook URL caused a key read.")
            return "private-key"
        })
        let event = WebhookEvent(type: .meetingStarted, conversationId: conversationId,
            title: "Weekly sync", startedAt: startedAt)
        #expect(await client.send(event, to: URL(string: endpoint)) == .invalidURL)
    }

    @Test(arguments: ["https://webhook.example/events", "http://127.0.0.1:7789/events"])
    func acceptsHTTPAndHTTPSEndpoints(endpoint: String) {
        #expect(WebhookClient.endpoint(from: " \(endpoint)\n")?.absoluteString == endpoint)
    }
}

private final class WebhookTestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(message)
    }
}

private final class WebhookURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func webhookSession(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
    WebhookURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WebhookURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func webhookBody(_ request: URLRequest) throws -> Data {
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
