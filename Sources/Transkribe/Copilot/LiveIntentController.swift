import Foundation
import Observation
import OSLog
import TranskribeCore

@MainActor
@Observable
final class LiveIntentController {
    private struct Update {
        let track: String
        let segments: [Segment]
        let committedAt: Date
    }

    let meetingID: UUID
    private(set) var cards: [IntentCard] = []
    private(set) var mutedIntentIDs = Set<String>()
    private(set) var notice: String?
    private weak var model: AppModel?
    private weak var ai: AIService?
    private let startedAt: Date
    private let config: IntentConfig
    private let decisionModel: AIModel
    private var session: LiveIntentSession?
    private var incoming: [Update] = []
    private var timer: Task<Void, Never>?
    private var evaluation: Task<Void, Never>?
    private var actions: [String: Task<Void, Never>] = [:]
    private var actionIntents: [String: String] = [:]
    private var stopped = false
    private var lastLoggedUsage: IntentTokenUsage?
    private let meter = IntentTokenCounter()
    private let logger = Logger(subsystem: "Transkribe", category: "Intents")

    init(meetingID: UUID, startedAt: Date, model: AppModel, ai: AIService) {
        self.meetingID = meetingID
        self.startedAt = startedAt
        self.model = model
        self.ai = ai
        decisionModel = model.copilotSettings.decisionModel
        let loaded = IntentConfig.load(from: TranscriptStore.supportDirectory.appendingPathComponent("intents.json"))
        config = loaded.config
        notice = loaded.error
    }

    func receive(track: String, committed: [Segment], at now: Date) {
        guard !stopped, model?.copilotSettings.intents == true, !config.intents.isEmpty else { return }
        incoming.append(Update(track: track, segments: committed, committedAt: now))
        if timer == nil {
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self?.evaluate()
                }
            }
        }
        evaluate()
    }

    func pause() {
        timer?.cancel()
        timer = nil
        evaluation?.cancel()
        for task in actions.values { task.cancel() }
    }

    func finish() async {
        timer?.cancel()
        timer = nil
        if let evaluation { await evaluation.value }
        evaluate(force: true)
        if let evaluation { await evaluation.value }
        logUsage(await meter.usage())
    }

    func mute(_ intentID: String) {
        mutedIntentIDs.insert(intentID)
        let session = session
        Task { await session?.mute(intentID) }
        for (key, value) in actionIntents where value == intentID { actions[key]?.cancel() }
        for index in cards.indices where cards[index].intentID == intentID {
            cards[index].status = "Muted for this meeting"
        }
    }

    func clearChat() {
        evaluation?.cancel()
        for task in actions.values { task.cancel() }
        cards.removeAll()
    }

    func dismiss(_ id: UUID) {
        cards.removeAll { $0.id == id }
    }

    private func evaluate(force: Bool = false) {
        guard evaluation == nil, !stopped, model?.copilotSettings.intents == true, !config.intents.isEmpty else { return }
        evaluation = Task { [weak self] in
            guard let self else { return }
            defer { evaluation = nil }
            do {
                guard let model, let ai else { return }
                guard model.copilotSettings.decisionModel == decisionModel else {
                    notice = "Background work stopped. The decision model changed. Start a new meeting to use it."
                    stopped = true
                    pause()
                    return
                }
                if session == nil {
                    guard let provider = await ai.decisionProvider() else {
                        notice = ai.decisionModelNotice
                        stopped = true
                        pause()
                        return
                    }
                    try Task.checkCancellation()
                    guard model.copilotSettings.intents else { return }
                    session = LiveIntentSession(meetingID: meetingID, startedAt: startedAt, config: config,
                        provider: IntentMeteredProvider(base: provider, counter: meter), model: decisionModel)
                    for id in mutedIntentIDs { await session?.mute(id) }
                }
                guard let session else { return }
                repeat {
                    let updates = incoming
                    incoming.removeAll()
                    for update in updates {
                        await session.receive(track: update.track, committed: update.segments, at: update.committedAt)
                    }
                    let reliable = model.transcript(meetingID)?.tracks.contains { $0.source == .microphone } == true
                        && model.transcript(meetingID)?.tracks.contains { $0.source == .system } == true
                    let dispatch = try await session.evaluate(enabled: model.copilotSettings.intents,
                        meIsReliable: reliable, force: force)
                    try Task.checkCancellation()
                    if let dispatch, model.copilotSettings.intents,
                       !mutedIntentIDs.contains(dispatch.match.intent.id) {
                        run(dispatch)
                    }
                } while !incoming.isEmpty && model.copilotSettings.intents
                logUsage(await meter.usage())
            } catch is CancellationError {
            } catch {
                notice = "Background work stopped. \(error.localizedDescription)"
                stopped = true
                pause()
            }
        }
    }

    private func run(_ dispatch: IntentDispatch) {
        guard let model, let ai, let transcript = model.transcript(meetingID) else { return }
        let intent = dispatch.match.intent
        cards.append(IntentCard(id: dispatch.id, intentID: intent.id,
            title: intent.id.replacingOccurrences(of: "_", with: " ").capitalized,
            request: dispatch.match.request, status: "Preparing action"))
        actionIntents[dispatch.taskKey] = intent.id
        actions[dispatch.taskKey] = Task {
            defer {
                actions[dispatch.taskKey] = nil
                actionIntents[dispatch.taskKey] = nil
            }
            do {
                try Task.checkCancellation()
                guard model.copilotSettings.intents, !mutedIntentIDs.contains(intent.id) else { return }
                switch intent.action.destination {
                case .webhook:
                    let payload = try dispatch.webhookIntent()
                    let event = WebhookEvent(type: .intent, conversationId: meetingID, title: transcript.title,
                        startedAt: transcript.createdAt, intent: payload)
                    log(dispatch.lag(actionSentAt: Date()))
                    let result = await WebhookClient().send(event, to: model.copilotSettings.webhook)
                    setStatus(dispatch.id, result == .sent ? "Sent to Grok webhook" : result.message)
                case .ask:
                    let chosen = ai.selectedModel
                    guard ai.isAvailable(chosen), let provider = ai.provider(for: chosen) else {
                        throw AIError("The selected Ask model is unavailable.")
                    }
                    let providerWithMeter = IntentMeteredProvider(base: provider, counter: meter)
                    let stream = providerWithMeter.stream(model: chosen, system: dispatch.systemInstruction,
                        messages: [AIMessage(role: .user, text: try dispatch.quotedData(), origin: .intent)])
                    log(dispatch.lag(actionSentAt: Date()))
                    setStatus(dispatch.id, "Sent to \(chosen.displayName)")
                    var answer = ""
                    for try await delta in stream {
                        try Task.checkCancellation()
                        guard model.copilotSettings.intents, !mutedIntentIDs.contains(intent.id) else { throw CancellationError() }
                        answer += delta
                        if let index = cards.firstIndex(where: { $0.id == dispatch.id }) { cards[index].answer = answer }
                    }
                    try Task.checkCancellation()
                    model.update(meetingID, persist: true) {
                        var chat = $0.chat ?? AIChat()
                        chat.messages.append(AIMessage(role: .user, text: dispatch.match.request, origin: .intent))
                        chat.messages.append(AIMessage(role: .assistant, text: answer.isEmpty ? "(No answer)" : answer, origin: .intent))
                        $0.chat = chat
                    }
                    if let index = cards.firstIndex(where: { $0.id == dispatch.id }) { cards[index].answer = "" }
                    setStatus(dispatch.id, "Answered by \(chosen.displayName)")
                }
                logUsage(await meter.usage())
            } catch is CancellationError {
                setStatus(dispatch.id, "Action stopped")
            } catch {
                setStatus(dispatch.id, error.localizedDescription)
            }
        }
    }

    private func setStatus(_ id: UUID, _ status: String) {
        if let index = cards.firstIndex(where: { $0.id == id }) {
            cards[index].status = mutedIntentIDs.contains(cards[index].intentID) ? "Muted for this meeting" : status
        }
    }

    private func log(_ record: IntentLagRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return }
        logger.info("Intent lag: \(String(decoding: data, as: UTF8.self), privacy: .public) stt=\(record.transcriptionLag)s decision=\(record.decisionLag)s action=\(record.actionLag)s total=\(record.totalLag)s")
    }

    private func logUsage(_ usage: IntentTokenUsage) {
        guard usage != lastLoggedUsage else { return }
        lastLoggedUsage = usage
        logger.info("Meeting \(self.meetingID.uuidString, privacy: .public) estimated intent tokens: input=\(usage.input) output=\(usage.output)")
    }
}
