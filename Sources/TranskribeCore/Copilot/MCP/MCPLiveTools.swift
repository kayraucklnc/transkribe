import CoreFoundation
import Foundation

/// Optional MCP tools for current transcripts. The caller supplies snapshots that include pending text.
/// The snapshot and clock closures must support every thread that calls the server.
public struct MCPLiveTools {
    public let answerStore: AnswerStore
    private let readScopeDays: Int
    private let snapshots: () -> [MCPConversationSnapshot]
    private let now: () -> Date

    /// History scope uses the transcript creation time. Supply the stop time for ended recordings that can receive answers.
    public init(snapshots: @escaping () -> [MCPConversationSnapshot], readScopeDays: Int = 7,
                now: @escaping () -> Date = Date.init, answerStore: AnswerStore? = nil) {
        self.readScopeDays = max(0, readScopeDays)
        self.snapshots = snapshots
        self.now = now
        self.answerStore = answerStore ?? AnswerStore(snapshots: snapshots, now: now)
    }

    public var tools: [MCPTool] {
        [
            MCPTool(name: "list_live_conversations", description: "List live conversations with their IDs, titles, dates, and participants.",
                    properties: [:], required: []) { _, library in
                let live = snapshots().filter(\.isLive).map { readableTranscript($0.transcript) }
                guard !live.isEmpty else { return ("No live conversations.", false) }
                return (ConversationLibrary(transcripts: live, people: library.people).listConversations(person: nil), false)
            },
            MCPTool(name: "read_conversation", description: "Read a conversation from its current transcript. Use from and to in seconds to select a time range.",
                    properties: ["id": ["type": "string", "description": "Supply the conversation ID."],
                                 "from": ["type": "number", "description": "Set the optional start time in seconds."],
                                 "to": ["type": "number", "description": "Set the optional end time in seconds."]], required: ["id"]) {
                arguments, library in read(arguments, library: library)
            },
            MCPTool(name: "post_answer",
                    description: "Create an answer for a live conversation or a conversation that ended less than 24 hours ago. The result contains answerId.",
                    properties: ["conversationId": ["type": "string", "description": "Supply the conversation ID."],
                                 "markdown": ["type": "string", "description": "Supply Markdown text with at most 32 KB in UTF-8."]],
                    required: ["conversationId", "markdown"]) { arguments, _ in post(arguments) },
            MCPTool(name: "update_answer",
                    description: "Replace the answer text. Set final to true to prevent later updates. Each answer permits 30 updates per minute.",
                    properties: ["answerId": ["type": "string", "description": "Use the answerId from post_answer."],
                                 "markdown": ["type": "string", "description": "Supply replacement Markdown text with at most 32 KB in UTF-8."],
                                 "final": ["type": "boolean", "description": "True prevents later updates to this answer."]],
                    required: ["answerId", "markdown", "final"]) { arguments, _ in update(arguments) },
        ]
    }

    public var scopeFilter: (Transcript) -> Bool {
        { transcript in
            let live = snapshots().contains { $0.transcript.id == transcript.id && $0.isLive }
            return canRead(transcript, isLive: live, at: now())
        }
    }

    private func read(_ arguments: [String: Any], library: ConversationLibrary) -> MCPToolResult {
        guard let id = arguments["id"] as? String, let uuid = UUID(uuidString: id) else {
            return ("A valid conversation ID is required.", true)
        }
        let current = snapshots()
        let time = now()
        let liveIDs = Set(current.filter(\.isLive).map { $0.transcript.id })
        var transcripts = library.transcripts.filter { canRead($0, isLive: liveIDs.contains($0.id), at: time) }
        for snapshot in current {
            transcripts.removeAll { $0.id == snapshot.transcript.id }
            if canRead(snapshot.transcript, isLive: snapshot.isLive, at: time) {
                transcripts.append(readableTranscript(snapshot.transcript))
            }
        }
        guard transcripts.contains(where: { $0.id == uuid }) else {
            return ("The conversation ID is unknown or outside the read scope.", true)
        }
        answerStore.recordRead(conversationId: uuid)
        let result = ConversationLibrary(transcripts: transcripts, people: library.people)
            .conversation(id: id, from: number(arguments["from"]), to: number(arguments["to"]))
        return (result, false)
    }

    private func post(_ arguments: [String: Any]) -> MCPToolResult {
        guard let id = arguments["conversationId"] as? String, let uuid = UUID(uuidString: id),
              let markdown = arguments["markdown"] as? String else {
            return ("A valid conversationId and Markdown text are required.", true)
        }
        do {
            return try answerResult(answerStore.post(conversationId: uuid, markdown: markdown))
        } catch {
            return (error.localizedDescription, true)
        }
    }

    private func update(_ arguments: [String: Any]) -> MCPToolResult {
        guard let id = arguments["answerId"] as? String, let uuid = UUID(uuidString: id),
              let markdown = arguments["markdown"] as? String, let final = arguments["final"] as? NSNumber,
              CFGetTypeID(final) == CFBooleanGetTypeID() else {
            return ("A valid answerId, Markdown text, and a final Boolean are required.", true)
        }
        do {
            return try answerResult(answerStore.update(answerId: uuid, markdown: markdown, final: final.boolValue))
        } catch {
            return (error.localizedDescription, true)
        }
    }

    private func answerResult(_ answer: AgentAnswer) throws -> MCPToolResult {
        let data = try JSONSerialization.data(withJSONObject: ["answerId": answer.id.uuidString, "final": answer.isFinal])
        return (String(decoding: data, as: UTF8.self), false)
    }

    private func canRead(_ transcript: Transcript, isLive: Bool, at time: Date) -> Bool {
        let age = time.timeIntervalSince(transcript.createdAt)
        return isLive || (age >= 0 && age <= Double(readScopeDays) * 86_400)
    }

    private func number(_ value: Any?) -> TimeInterval? {
        (value as? Double) ?? (value as? Int).map(Double.init)
    }

    private func readableTranscript(_ transcript: Transcript) -> Transcript {
        var copy = transcript
        copy.status = .done
        return copy
    }
}
