import Foundation
import Testing
@testable import TranskribeCore

private let choiceResponse = """
{"model":"typesafe/jev-1.14","answers":{"intent":{"type":"choice","choice":"ask","confidence":0.91,
"probabilities":{"ask":0.95,"none":0.05}}},"usage":{"input_tokens":476,"output_tokens":70,"cost":0.000019992}}
"""

private let intentQuestion = DecisionQuestion(type: .choice, instructions: "Select the meeting intent.",
                                            criteria: ["ask": "The speaker asks Grok for help.", "none": "No request."])

@Suite(.serialized) struct OpenRouterDecisionClientTests {
    @Test func sendsAChoiceQuestionAndReturnsItsAnswer() async throws {
        let session = decisionSession { request in
            #expect(request.url?.absoluteString == "https://openrouter.ai/api/alpha/decisions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            let data = try decisionRequestBody(request)
            #expect(!String(decoding: data, as: UTF8.self).contains("private-test-key"))
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(body.keys) == ["model", "state", "questions"])
            #expect(body["model"] as? String == "~typesafe/jev-latest")
            #expect(body["state"] as? String == "Me: Grok, check Acme. ğüşİ 🌍")
            let questions = try #require(body["questions"] as? [String: [String: Any]])
            #expect(Set(questions.keys) == ["intent"])
            #expect(questions["intent"]?["type"] as? String == "choice")
            #expect(questions["intent"]?["instructions"] as? String == "Select the meeting intent.")
            #expect(questions["intent"]?["criteria"] as? [String: String]
                == ["ask": "The speaker asks Grok for help.", "none": "No request."])
            return (200, choiceResponse)
        }
        defer { session.invalidateAndCancel() }
        let client: any DecisionClient = OpenRouterDecisionClient(session: session, apiKey: { " private-test-key\n" })
        let answers = try await client.decide(model: .jev, state: "Me: Grok, check Acme. ğüşİ 🌍",
                                              questions: ["intent": intentQuestion])
        #expect(answers["intent"]?.type == .choice)
        #expect(answers["intent"]?.choice == "ask")
        #expect(answers["intent"]?.confidence == 0.91)
        #expect(answers["intent"]?.probabilities == ["ask": 0.95, "none": 0.05])
    }

    @Test func reportsUsageOnceForTheWholeRequest() async throws {
        let usage = DecisionUsageRecorder()
        let session = decisionSession { _ in (200, choiceResponse) }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" }, onUsage: { usage.append($0) })
        _ = try await client.decide(model: .luna, state: "Meeting", questions: ["intent": intentQuestion])
        #expect(usage.values == [DecisionUsage(inputTokens: 476, outputTokens: 70, cost: 0.000019992)])
    }

    @Test func decisionUsageReachesTheMeetingCounterBeforeTheRequestReturns() async throws {
        let counter = IntentTokenCounter()
        let session = decisionSession { _ in (200, choiceResponse) }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" }, onUsage: {
            await counter.record($0)
        })
        _ = try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        await counter.record(inputCharacters: 8, outputCharacters: 4)
        let usage = await counter.usage()
        #expect(usage.input == 478)
        #expect(usage.output == 71)
        #expect(usage.total == 549)
    }

    @Test func rejectsAnUnknownChoiceWithoutReportingSuccessfulUsage() async {
        let usage = DecisionUsageRecorder()
        let session = decisionSession { _ in (200, choiceResponse.replacingOccurrences(of: "\"choice\":\"ask\"",
                                                                                       with: "\"choice\":\"delete\"")) }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" }, onUsage: { usage.append($0) })
        await #expect(throws: AIError("OpenRouter returned an unknown decision choice.")) {
            try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        }
        #expect(usage.values.isEmpty)
    }

    @Test func sendsNoulAndChoiceTogetherAndReportsUsageOnce() async throws {
        let usage = DecisionUsageRecorder()
        let session = decisionSession { request in
            let body = try #require(JSONSerialization.jsonObject(with: decisionRequestBody(request)) as? [String: Any])
            let questions = try #require(body["questions"] as? [String: [String: Any]])
            #expect(questions["relevant"]?["type"] as? String == "noul")
            #expect(questions["relevant"]?["instructions"] as? String == "Does this concern Acme?")
            #expect(questions["relevant"]?["criteria"] as? [String: String]
                == ["true": "Acme is discussed.", "false": "Another topic is discussed."])
            return (200, """
            {"model":"typesafe/jev-1.14","answers":{"intent":{"type":"choice","choice":"ask"},
            "relevant":{"type":"noul","noul":0.96}},"usage":{"input_tokens":300,"output_tokens":20}}
            """)
        }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" }, onUsage: { usage.append($0) })
        let answers = try await client.decide(model: .jev, state: "Meeting", questions: [
            "intent": intentQuestion,
            "relevant": DecisionQuestion(type: .noul, instructions: "Does this concern Acme?",
                                         criteria: ["true": "Acme is discussed.", "false": "Another topic is discussed."]),
        ])
        #expect(answers["intent"]?.choice == "ask")
        #expect(answers["intent"]?.confidence == nil)
        #expect(answers["intent"]?.probabilities == nil)
        #expect(answers["relevant"]?.type == .noul)
        #expect(answers["relevant"]?.noul == 0.96)
        #expect(usage.values == [DecisionUsage(inputTokens: 300, outputTokens: 20)])
    }

    @Test(arguments: [
        (401, "OpenRouter rejected your API key. Check it in Settings."),
        (402, "Your OpenRouter credits are exhausted. Add credits to your OpenRouter account."),
        (429, "You reached the OpenRouter rate limit. Wait a minute and try again."),
        (503, "OpenRouter has a server error. Try again later."),
        (418, "OpenRouter returned an HTTP error (418)."),
    ])
    func mapsHTTPErrorsWithoutExposingServerContent(status: Int, message: String) async {
        let usage = DecisionUsageRecorder()
        let session = decisionSession { _ in (status, #"{"error":{"message":"private-test-key secret transcript"}}"#) }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" }, onUsage: { usage.append($0) })
        await #expect(throws: AIError(message)) {
            try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        }
        #expect(usage.values.isEmpty)
    }

    @Test(arguments: [
        (URLError.Code.timedOut, "OpenRouter took too long to decide. Try again."),
        (.notConnectedToInternet, "Cannot reach OpenRouter. Check your connection and try again."),
    ])
    func mapsTransportErrors(code: URLError.Code, message: String) async {
        let session = decisionSession { request in
            #expect(request.timeoutInterval == 30)
            throw URLError(code)
        }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" })
        await #expect(throws: AIError(message)) {
            try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        }
    }

    @Test func cancellationStopsTheActiveRequest() async {
        let started = AsyncStream<Void>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        let usage = DecisionUsageRecorder()
        let session = decisionSession { _ in (200, choiceResponse) }
        DecisionURLProtocol.completesResponse = false
        DecisionURLProtocol.onStart = { started.continuation.yield() }
        DecisionURLProtocol.onStop = { stopped.continuation.yield() }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                Issue.record("Cancellation did not stop the decision request.")
                session.invalidateAndCancel()
                started.continuation.finish()
                stopped.continuation.finish()
            }
        }
        defer {
            timeout.cancel()
            session.invalidateAndCancel()
            started.continuation.finish()
            stopped.continuation.finish()
        }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" }, onUsage: { usage.append($0) })
        let task = Task {
            try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        }
        for await _ in started.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        var didStop = false
        for await _ in stopped.stream {
            didStop = true
            break
        }
        #expect(didStop)
        #expect(usage.values.isEmpty)
    }

    @Test(arguments: [
        "not-json",
        #"{"answers":{},"usage":{"input_tokens":1,"output_tokens":1}}"#,
        choiceResponse.replacingOccurrences(of: "\"intent\":", with: "\"unrequested\":"),
        choiceResponse.replacingOccurrences(of: "\"type\":\"choice\"", with: "\"type\":\"score\""),
        choiceResponse.replacingOccurrences(of: "\"type\":\"choice\"", with: "\"type\":\"noul\""),
        choiceResponse.replacingOccurrences(of: "\"choice\":\"ask\",", with: ""),
        choiceResponse.replacingOccurrences(of: "0.91", with: "1.1"),
        choiceResponse.replacingOccurrences(of: "\"ask\":0.95", with: "\"unknown\":0.95"),
        choiceResponse.replacingOccurrences(of: "\"ask\":0.95", with: "\"ask\":-0.1"),
        choiceResponse.replacingOccurrences(of: "\"input_tokens\":476", with: "\"input_tokens\":-1"),
        choiceResponse.replacingOccurrences(of: "\"cost\":0.000019992", with: "\"cost\":-1"),
    ])
    func rejectsMalformedOrMismatchedResponses(body: String) async {
        let usage = DecisionUsageRecorder()
        let session = decisionSession { _ in (200, body) }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" }, onUsage: { usage.append($0) })
        await #expect(throws: AIError("OpenRouter returned an invalid decision response.")) {
            try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        }
        #expect(usage.values.isEmpty)
    }

    @Test(arguments: ["null", "-0.1", "1.1"])
    func rejectsInvalidNoulProbabilities(probability: String) async {
        let session = decisionSession { _ in
            (200, """
            {"answers":{"relevant":{"type":"noul","noul":\(probability)}},
            "usage":{"input_tokens":1,"output_tokens":1}}
            """)
        }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { "key" })
        await #expect(throws: AIError("OpenRouter returned an invalid decision response.")) {
            try await client.decide(model: .jev, state: "Meeting", questions: [
                "relevant": DecisionQuestion(type: .noul, instructions: "Is this relevant?",
                                             criteria: ["true": "Relevant.", "false": "Unrelated."]),
            ])
        }
    }

    @Test(arguments: [nil, "", " \n "] as [String?])
    func missingKeyNeverSendsTranscriptData(key: String?) async {
        let session = decisionSession { _ in
            Issue.record("The client sent transcript data without a key.")
            return (200, choiceResponse)
        }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: { key })
        await #expect(throws: AIError("Add an OpenRouter API key in Settings.")) {
            try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        }
    }

    @Test func cancellationBeforeTheCallDoesNotReadAKeyOrSendData() async {
        let gate = AsyncStream<Void>.makeStream()
        let session = decisionSession { _ in
            Issue.record("The client sent transcript data after cancellation.")
            return (200, choiceResponse)
        }
        defer { session.invalidateAndCancel() }
        let client = OpenRouterDecisionClient(session: session, apiKey: {
            Issue.record("The client read a key after cancellation.")
            return "key"
        })
        let task = Task {
            for await _ in gate.stream {}
            return try await client.decide(model: .jev, state: "Meeting", questions: ["intent": intentQuestion])
        }
        task.cancel()
        gate.continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

private final class DecisionUsageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [DecisionUsage] = []

    var values: [DecisionUsage] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ usage: DecisionUsage) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(usage)
    }
}

private final class DecisionURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    static var completesResponse = true
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?

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
            if Self.completesResponse { client?.urlProtocolDidFinishLoading(self) }
            Self.onStart?()
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { Self.onStop?() }
}

private func decisionSession(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
    DecisionURLProtocol.handler = handler
    DecisionURLProtocol.completesResponse = true
    DecisionURLProtocol.onStart = nil
    DecisionURLProtocol.onStop = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DecisionURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func decisionRequestBody(_ request: URLRequest) throws -> Data {
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
