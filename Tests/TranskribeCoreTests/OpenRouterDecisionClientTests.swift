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
}

private final class DecisionURLProtocol: URLProtocol {
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

private func decisionSession(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
    DecisionURLProtocol.handler = handler
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
