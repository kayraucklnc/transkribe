import Foundation
import Observation
import OSLog
import TranskribeCore

@MainActor
@Observable
final class LiveTopicGraphController {
    private static let logger = Logger(subsystem: "Transkribe", category: "TopicGraph")

    private(set) var graph: TopicGraph
    private(set) var notice: String?
    /// The chip uses the latest batch with a valid name, excluding unnamed batches.
    var lastNamedLag: TimeInterval? { graph.lagRecords.last { $0.namedAt != nil }?.namedLag }

    private let trackFiles: [String]
    private let onNotice: (String) -> Void
    private var session: LiveTopicGraphSession?
    private var delivery: Task<Void, Never>?
    private var drafts: [Int: String] = [:]
    private var finished = false
    private var discarded = false

    init(transcript: Transcript, startedAt: Date, settings: TopicGraphSettings,
         store: TopicGraphStore, openRouterKey: String?, onNotice: @escaping (String) -> Void) {
        graph = TopicGraph(meetingId: transcript.id)
        trackFiles = transcript.tracks.map(\.fileName)
        self.onNotice = onNotice
        guard let selection = TopicGraphModelSelection.resolve(settings: settings, openRouterKey: openRouterKey) else {
            let message = "The topic graph stopped for this meeting. Check the OpenRouter key and topic graph models in Settings."
            notice = message
            onNotice(message)
            return
        }
        session = LiveTopicGraphSession(meetingId: transcript.id, meetingStartedAt: startedAt, store: store,
            router: TopicRouter(client: OpenRouterDecisionClient(apiKey: { openRouterKey }), model: selection.decisionModel),
            namer: TopicNamer(provider: OpenRouterProvider(apiKey: { openRouterKey }),
                              model: selection.namingModel, settings: settings),
            onChange: { [weak self] graph, notice in await self?.accept(graph, notice: notice) })
    }

    func receive(_ progress: LiveTrackProgress, track: Int, offset: TimeInterval) {
        guard !finished, notice == nil, let session else { return }
        // Publish pending text synchronously, before any actor or network work.
        drafts[track] = progress.pending.map(\.text).joined(separator: " ")
        graph.draft = draftText
        let committedAt = Date()
        let previous = delivery
        delivery = Task {
            await previous?.value
            await session.receive(progress, track: track, offset: offset, at: committedAt)
        }
    }

    func finish(tracks: [AudioTrack], startedAt: Date?) async {
        guard !finished else { return }
        finished = true
        await delivery?.value
        delivery = nil
        drafts.removeAll()
        let offsets = Dictionary(uniqueKeysWithValues: trackFiles.enumerated().map { index, file in
            (index, tracks.first { $0.fileName == file }?.offset ?? graph.trackOffsets[index] ?? 0)
        })
        let summary = await session?.finish(trackOffsets: offsets, meetingStartedAt: startedAt)
            ?? TopicGraphLagSummary(records: [])
        graph.draft = ""
        Self.logger.info("Meeting \(self.graph.meetingId.uuidString, privacy: .public): \(summary.logLine, privacy: .public)")
    }

    func discard() async {
        discarded = true
        finished = true
        await delivery?.value
        await session?.cancel()
        delivery = nil
    }

    private var draftText: String {
        drafts.sorted { $0.key < $1.key }.map(\.value).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func accept(_ graph: TopicGraph, notice: String?) {
        guard !discarded else { return }
        self.graph = graph
        self.graph.draft = draftText
        if let notice, self.notice == nil {
            self.notice = notice
            onNotice(notice)
        }
    }
}

extension AppModel {
    func startTopicGraph(for transcript: Transcript, startedAt: Date) {
        guard copilotSettings.topicGraph, topicGraphs[transcript.id] == nil else { return }
        topicGraphs[transcript.id] = LiveTopicGraphController(transcript: transcript, startedAt: startedAt,
            settings: copilotSettings.topicGraphSettings, store: TopicGraphStore(rootDirectory: store.rootDirectory),
            openRouterKey: KeychainStore().get(account: OpenRouterKeychain.account),
            onNotice: { [weak self] message in self?.show(message: message) })
    }

    func finishTopicGraph(for id: Transcript.ID, startedAt: Date? = nil) async {
        guard let controller = topicGraphs[id] else { return }
        await controller.finish(tracks: transcript(id)?.tracks ?? [], startedAt: startedAt)
    }
}
