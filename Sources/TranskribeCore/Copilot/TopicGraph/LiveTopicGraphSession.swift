import Foundation

/// Runs routing, naming and persistence on an actor separate from the UI.
public actor LiveTopicGraphSession {
    private struct RangeKey: Hashable {
        let track: Int
        let start: TimeInterval
        let end: TimeInterval
    }

    private struct CommittedPoint {
        let point: TopicPointInput
        let committedAt: Date
    }

    public private(set) var graph: TopicGraph
    public private(set) var notice: String?
    private let store: TopicGraphStore
    private let router: TopicRouter
    private let namer: TopicNamer
    private let now: @Sendable () -> Date
    private let onChange: @Sendable (TopicGraph, String?) async -> Void
    private var scheduler: EvaluationScheduler
    private var meetingStartedAt: Date
    private var seen: Set<RangeKey> = []
    private var queued: [CommittedPoint] = []
    private var drafts: [Int: String] = [:]
    private var committedWordCount = 0
    private var worker: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var isFinishing = false
    private var isCancelled = false
    private var summary: TopicGraphLagSummary?

    public init(meetingId: UUID, meetingStartedAt: Date, store: TopicGraphStore,
                router: TopicRouter, namer: TopicNamer, scheduler: EvaluationScheduler = EvaluationScheduler(),
                now: @escaping @Sendable () -> Date = { Date() },
                onChange: @escaping @Sendable (TopicGraph, String?) async -> Void = { _, _ in }) {
        graph = TopicGraph(meetingId: meetingId)
        self.meetingStartedAt = meetingStartedAt
        self.store = store
        self.router = router
        self.namer = namer
        self.scheduler = scheduler
        self.now = now
        self.onChange = onChange
    }

    public func receive(_ progress: LiveTrackProgress, track: Int, offset: TimeInterval, at committedAt: Date = Date()) async {
        guard !isFinishing, notice == nil else { return }
        do {
            var offsets = graph.trackOffsets
            offsets[track] = offset
            try graph.reconcileTimeline(trackOffsets: offsets, meetingStartedAt: meetingStartedAt)
            drafts[track] = progress.pending.map(\.text).joined(separator: " ")
            graph.draft = drafts.sorted { $0.key < $1.key }.map(\.value).filter { !$0.isEmpty }.joined(separator: " ")
            for segment in progress.committed {
                let key = RangeKey(track: track, start: segment.start, end: segment.end)
                guard seen.insert(key).inserted else { continue }
                queued.append(.init(point: .init(track: track, start: segment.start, end: segment.end,
                                                text: segment.text, speaker: segment.speaker), committedAt: committedAt))
                committedWordCount += segment.text.split(whereSeparator: \.isWhitespace).count
            }
            startProcessing(force: false, at: committedAt)
            await onChange(graph, notice)
        } catch {
            await stop(error)
        }
    }

    /// Drains the last short batch, waits for requests, and saves the final capture offsets.
    @discardableResult
    public func finish(trackOffsets: [Int: TimeInterval], meetingStartedAt: Date? = nil) async -> TopicGraphLagSummary {
        if let summary { return summary }
        if isCancelled {
            await worker?.value
            return TopicGraphLagSummary(records: graph.lagRecords)
        }
        isFinishing = true
        wakeTask?.cancel()
        wakeTask = nil
        if let meetingStartedAt { self.meetingStartedAt = meetingStartedAt }
        do {
            try graph.reconcileTimeline(trackOffsets: trackOffsets, meetingStartedAt: self.meetingStartedAt)
            startProcessing(force: true, at: now())
            await worker?.value
            if isCancelled { return TopicGraphLagSummary(records: graph.lagRecords) }
            graph.draft = ""
            try graph.reconcileTimeline(trackOffsets: trackOffsets, meetingStartedAt: self.meetingStartedAt)
            try store.save(graph)
        } catch {
            await stop(error)
        }
        let result = TopicGraphLagSummary(records: graph.lagRecords)
        summary = result
        await onChange(graph, notice)
        return result
    }

    /// Prevents future writes before the caller removes the meeting directory.
    public func cancel() {
        isCancelled = true
        isFinishing = true
        queued.removeAll()
        wakeTask?.cancel()
        wakeTask = nil
        worker?.cancel()
    }

    private func startProcessing(force: Bool, at date: Date) {
        guard worker == nil, notice == nil, !queued.isEmpty else { return }
        if force || scheduler.shouldEvaluate(committedWordCount: committedWordCount, at: date) {
            wakeTask?.cancel()
            wakeTask = nil
            worker = Task { await drain() }
        } else if wakeTask == nil {
            wakeTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                await self?.wake()
            }
        }
    }

    private func wake() {
        wakeTask = nil
        startProcessing(force: true, at: now())
    }

    private func drain() async {
        // Each request finishes before the next begins. New callbacks append to queued.
        while notice == nil, !queued.isEmpty {
            let batch = queued
            queued.removeAll()
            scheduler.didEvaluate(committedWordCount: committedWordCount, at: now())
            do {
                guard let proposal = try await router.route(batch.map(\.point), in: graph) else { continue }
                guard !isCancelled else { break }
                let previousCount = graph.points.count
                guard let topicId = try graph.apply(proposal) else { continue }
                let points = Array(graph.points.dropFirst(previousCount))
                let end = points.map { $0.end + (graph.trackOffsets[$0.track] ?? 0) }.max() ?? 0
                let recordIndex = graph.lagRecords.count
                graph.lagRecords.append(.init(pointIds: points.map(\.id),
                    speechEndedAt: meetingStartedAt.addingTimeInterval(end),
                    committedAt: batch.map(\.committedAt).max() ?? now(), routedAt: now()))
                // Preserve a routing sample even if naming fails or returns malformed data.
                try store.save(graph)
                await onChange(graph, notice)
                guard !isCancelled else { break }
                if let name = try await namer.name(topicId: topicId, in: graph) {
                    guard !isCancelled else { break }
                    try graph.setName(topicId: topicId, label: name.label, summary: name.summary)
                    graph.lagRecords[recordIndex].namedAt = now()
                }
                guard !isCancelled else { break }
                try store.save(graph)
                await onChange(graph, notice)
            } catch {
                await stop(error)
            }
        }
        worker = nil
    }

    private func stop(_ error: Error) async {
        guard !isCancelled else { return }
        if notice == nil { notice = "The topic graph stopped for this meeting. \(error.localizedDescription)" }
        wakeTask?.cancel()
        wakeTask = nil
        await onChange(graph, notice)
    }
}
