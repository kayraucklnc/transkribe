import Foundation
import Testing
@testable import TranskribeCore

@Suite struct LiveTopicGraphSessionTests {
    @Test(arguments: [false, true])
    func providerFailureStopsTheMeetingWithoutFallback(namingFails: Bool) async throws {
        let root = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let client = LiveGraphDecisionFake(error: namingFails ? nil : AIError("The routing request failed."))
        let provider = FakeAIProvider(budget: 100_000) { _ in throw AIError("The naming request failed.") }
        let notices = AsyncStream<String>.makeStream()
        defer { notices.continuation.finish() }
        let store = TopicGraphStore(rootDirectory: root)
        let session = LiveTopicGraphSession(meetingId: id, meetingStartedAt: Date(), store: store,
            router: TopicRouter(client: client, model: .jev),
            namer: TopicNamer(provider: provider, model: provider.models[0]),
            scheduler: EvaluationScheduler(minNewWords: 1), onChange: { _, notice in
                if let notice { notices.continuation.yield(notice) }
            })
        await session.receive(progress(committed: [.init(start: 0, end: 1, text: "First")]), track: 0, offset: 0)
        var iterator = notices.stream.makeAsyncIterator()
        #expect(await iterator.next()?.contains("stopped for this meeting") == true)
        await session.receive(progress(committed: [.init(start: 1, end: 2, text: "Later")]), track: 0, offset: 0)
        await session.finish(trackOffsets: [0: 0])
        let graph = store.load(meetingId: id).graph
        #expect(await client.callCount == 1)
        #expect(provider.calls.count == (namingFails ? 1 : 0))
        #expect(graph.points.count == (namingFails ? 1 : 0))
        #expect(graph.lagRecords.count == (namingFails ? 1 : 0))
        #expect(graph.lagRecords.allSatisfy { $0.namedAt == nil })
    }

    @Test func cancellationPreventsAnInflightRequestFromRecreatingDeletedGraphData() async throws {
        let root = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let store = TopicGraphStore(rootDirectory: root)
        let client = LiveGraphDecisionFake(holdsFirstCall: true)
        let provider = FakeAIProvider(budget: 100_000) { _ in "{}" }
        let session = LiveTopicGraphSession(meetingId: id, meetingStartedAt: Date(), store: store,
            router: TopicRouter(client: client, model: .jev),
            namer: TopicNamer(provider: provider, model: provider.models[0]),
            scheduler: EvaluationScheduler(minNewWords: 1))
        await session.receive(progress(committed: [.init(start: 0, end: 1, text: "First")]), track: 0, offset: 0)
        await client.waitForFirstCall()
        await session.cancel()
        await client.release()
        await session.finish(trackOffsets: [0: 0])
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: id).path))
        #expect(provider.calls.isEmpty)
    }

    @Test func retainsRangesAndDraftWhileARequestRuns() async throws {
        let root = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let client = LiveGraphDecisionFake(holdsFirstCall: true)
        let provider = FakeAIProvider(budget: 100_000) { _ in
            #"{"label":"Pricing","summary":"Set the price."}"#
        }
        let store = TopicGraphStore(rootDirectory: root)
        let session = LiveTopicGraphSession(meetingId: id, meetingStartedAt: Date(), store: store,
            router: TopicRouter(client: client, model: .jev),
            namer: TopicNamer(provider: provider, model: provider.models[0]),
            scheduler: EvaluationScheduler(minNewWords: 1))
        let first = RawSegment(start: 0, end: 1, text: "First")
        let second = RawSegment(start: 1, end: 2, text: "Second")
        await session.receive(progress(committed: [first]), track: 0, offset: 0)
        await client.waitForFirstCall()
        await session.receive(progress(committed: [first, second], pending: [
            .init(start: 2, end: 3, text: "Still speaking"),
        ]), track: 0, offset: 0)
        await session.receive(progress(committed: [first]), track: 1, offset: 4)
        #expect(await session.graph.draft == "Still speaking")
        #expect(await client.callCount == 1)
        await client.release()
        await session.finish(trackOffsets: [0: 0, 1: 5])
        let graph = store.load(meetingId: id).graph
        #expect(graph.points.map(\.text) == ["First", "Second", "First"])
        #expect(graph.points.map(\.track) == [0, 0, 1])
        #expect(graph.points.map(\.start) == [0, 1, 0])
        #expect(graph.lagRecords.count == 2)
        #expect(graph.lagRecords[1].pointIds.count == 2)
        #expect(graph.lagRecords[1].namedAt == nil)
        #expect(graph.topics.first?.lastSec == 6)
        #expect(await client.maxActive == 1)
        #expect(await client.ranOnMainThread == false)
    }

    @Test func finalShortBatchRoutesWithoutAnotherProgressCallback() async throws {
        let root = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TopicGraphStore(rootDirectory: root)
        let id = UUID()
        let start = Date(timeIntervalSince1970: 100)
        let client = LiveGraphDecisionFake()
        let provider = FakeAIProvider(budget: 100_000) { _ in
            #"{"label":"Pricing","summary":"Set the price."}"#
        }
        let session = LiveTopicGraphSession(meetingId: id, meetingStartedAt: start, store: store,
            router: TopicRouter(client: client, model: .jev),
            namer: TopicNamer(provider: provider, model: provider.models[0]),
            scheduler: EvaluationScheduler(now: start), now: { start.addingTimeInterval(8) })
        await session.receive(progress(pending: [.init(start: 1, end: 2, text: "Draft")]), track: 0,
                              offset: 0, at: start.addingTimeInterval(3))
        #expect(await session.graph.draft == "Draft")
        #expect(await client.callCount == 0)
        await session.receive(progress(committed: [.init(start: 1, end: 2, text: "Price")]), track: 0,
                              offset: 0, at: start.addingTimeInterval(4))
        #expect(await client.callCount == 0)
        let summary = await session.finish(trackOffsets: [0: 1], meetingStartedAt: start)
        let loaded = store.load(meetingId: id)
        #expect(loaded.error == nil)
        #expect(loaded.graph.points.map(\.text) == ["Price"])
        #expect(loaded.graph.topics.first?.label == "Pricing")
        #expect(loaded.graph.topics.first?.firstSec == 2)
        #expect(loaded.graph.draft.isEmpty)
        let record = try #require(loaded.graph.lagRecords.first)
        #expect(record.sttLag == 1)
        #expect(record.graphLag == 5)
        #expect(record.namedLag == 5)
        #expect(summary.routedSampleCount == 1)
        #expect(await client.callCount == 1)
    }
}

private func progress(committed: [RawSegment] = [], pending: [RawSegment] = []) -> LiveTrackProgress {
    .init(committed: committed, pending: pending, committedUntil: committed.last?.end ?? 0,
          availableDuration: 10, turns: [], language: "en")
}

private actor LiveGraphDecisionFake: DecisionClient {
    private(set) var callCount = 0
    private(set) var maxActive = 0
    private(set) var ranOnMainThread = false
    private var active = 0
    private let holdsFirstCall: Bool
    private let error: AIError?
    private var blocked: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(holdsFirstCall: Bool = false, error: AIError? = nil) {
        self.holdsFirstCall = holdsFirstCall
        self.error = error
    }

    func waitForFirstCall() async {
        if callCount > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() { blocked?.resume(); blocked = nil }

    func decide(model: DecisionModel, state: String,
                questions: [String: DecisionQuestion]) async throws -> [String: DecisionAnswer] {
        callCount += 1
        active += 1
        maxActive = max(maxActive, active)
        ranOnMainThread = ranOnMainThread || Thread.isMainThread
        defer { active -= 1 }
        if holdsFirstCall, callCount == 1 {
            await withCheckedContinuation {
                blocked = $0
                started?.resume()
                started = nil
            }
        }
        if let error { throw error }
        return ["route": .init(type: .choice, choice: "continue"),
                "kind": .init(type: .choice, choice: "statement")]
    }
}
