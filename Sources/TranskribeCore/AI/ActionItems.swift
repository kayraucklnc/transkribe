import Foundation

/// Something someone agreed to do, found in a conversation.
public struct ActionItem: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var task: String
    /// Who will do it, as named in the transcript ("Me" for the user).
    public var owner: String?
    /// When, in the words used ("Friday", "next week").
    public var due: String?
    /// Where it was said, in seconds.
    public var time: TimeInterval?
    public var isDone = false

    public init(task: String, owner: String? = nil, due: String? = nil, time: TimeInterval? = nil) {
        self.task = task
        self.owner = owner
        self.due = due
        self.time = time
    }
}

/// Finds commitments and next steps with the user's chosen model.
public enum ActionItems {
    public static func extract(from transcript: Transcript, provider: any AIProvider, model: AIModel) async throws -> [ActionItem] {
        let lines = TranscriptPromptBuilder.lines(of: transcript)
        guard !lines.isEmpty else { throw AIError("This conversation has no text yet.") }
        let budget = provider.contextCharacterBudget(for: model) - 1_000
        let rendered = lines.joined(separator: "\n")
        let parts = rendered.count <= budget ? [rendered] : TranscriptPromptBuilder.chunks(of: transcript, maxCharacters: max(1_000, budget))
        var items: [ActionItem] = []
        for part in parts {
            try Task.checkCancellation()
            var reply = ""
            for try await delta in provider.stream(model: model, system: system(for: transcript),
                                                   messages: [AIMessage(role: .user, text: "<transcript>\n\(part)\n</transcript>")]) {
                reply += delta
            }
            for item in try parse(reply) where !items.contains(where: { $0.task.lowercased() == item.task.lowercased() }) {
                items.append(item)
            }
        }
        return items
    }

    static func system(for transcript: Transcript) -> String {
        let language = Prompts.languageName(for: transcript.language) ?? "the language of the conversation"
        return """
        You read a transcript of a conversation and list its action items: concrete things someone \
        agreed or was asked to do, and decided next steps. Skip vague ideas, small talk and things already done.
        Write each task as a short imperative in \(language). Use the speaker names exactly as in the \
        transcript for "owner" ("Me" is the user); null if unclear. "due" is the deadline in the words used, or null. \
        "time" is the [m:ss] timestamp where it was said.
        Reply with only a JSON array, e.g. [{"task": "...", "owner": "...", "due": null, "time": "12:30"}]. \
        Reply [] if there are none.
        """
    }

    /// The JSON array in the model's reply, tolerating code fences and surrounding text.
    public static func parse(_ reply: String) throws -> [ActionItem] {
        guard let open = reply.firstIndex(of: "["), let close = reply.lastIndex(of: "]"), open < close else {
            throw AIError("The model didn't return a list of to-dos.")
        }
        struct Raw: Decodable { var task: String; var owner: String?; var due: String?; var time: String? }
        let raws = try JSONDecoder().decode([Raw].self, from: Data(reply[open...close].utf8))
        return raws.compactMap { raw in
            let task = raw.task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { return nil }
            return ActionItem(task: task, owner: raw.owner?.nilIfBlank, due: raw.due?.nilIfBlank, time: raw.time.flatMap(seconds))
        }
    }

    static func seconds(_ stamp: String) -> TimeInterval? {
        let parts = stamp.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).split(separator: ":").compactMap { Double($0) }
        guard (2...3).contains(parts.count) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
    }
}
