import Foundation

/// A minimal Model Context Protocol server (JSON-RPC over stdio, one message per line) that
/// exposes the conversation library as tools, so an AI client can look things up itself.
public final class MCPServer: @unchecked Sendable {
    private let library: () -> ConversationLibrary

    public init(library: @escaping () -> ConversationLibrary) {
        self.library = library
    }

    public static let tools: [[String: Any]] = [
        tool("search_conversations",
             "Search every recorded conversation for lines containing the given words (accent- and case-insensitive; Turkish, English, Italian…). Returns the best matching lines with conversation id, title, date, participants and timestamps. Search in the language the conversation was held in; try synonyms if nothing matches.",
             ["query": ["type": "string", "description": "Words to look for"],
              "limit": ["type": "integer", "description": "Maximum lines to return (default 25)"]], required: ["query"]),
        tool("read_conversation",
             "Read a conversation (or part of it) by id: title, date, participants (who is the user), whether it's a group or one-to-one, its place in an ongoing conversation, summary, and timestamped lines. Use from/to (seconds) to read a section around search hits.",
             ["id": ["type": "string", "description": "Conversation id"],
              "from": ["type": "number", "description": "Start, in seconds (optional)"],
              "to": ["type": "number", "description": "End, in seconds (optional)"]], required: ["id"]),
        tool("list_conversations",
             "List conversations, newest first, with id, date, length, participants, kind and a one-line summary when available. Optionally only those with a given person.",
             ["person": ["type": "string", "description": "Only conversations with this person (part of a name)"],
              "limit": ["type": "integer", "description": "Maximum conversations (default 30)"]], required: []),
        tool("list_people",
             "List the people the user talks with: name, email addresses, number of conversations and when they last talked.",
             [:], required: []),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any]]
    }

    /// Runs a tool by name. Shared with in-app agents that don't speak MCP.
    public func call(_ name: String, arguments: [String: Any]) -> (text: String, isError: Bool) {
        let library = library()
        switch name {
        case "search_conversations":
            guard let query = arguments["query"] as? String else { return ("Missing “query”.", true) }
            return (library.search(query: query, limit: (arguments["limit"] as? Int) ?? 25), false)
        case "read_conversation":
            guard let id = arguments["id"] as? String else { return ("Missing “id”.", true) }
            return (library.conversation(id: id, from: number(arguments["from"]), to: number(arguments["to"])), false)
        case "list_conversations":
            return (library.listConversations(person: arguments["person"] as? String, limit: (arguments["limit"] as? Int) ?? 30), false)
        case "list_people":
            return (library.listPeople(), false)
        default:
            return ("Unknown tool \(name).", true)
        }
    }

    /// Handles one JSON-RPC message; returns the reply line, or nil for notifications.
    public func handle(line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return reply(id: NSNull(), error: (-32700, "Parse error"))
        }
        let method = message["method"] as? String ?? ""
        guard let id = message["id"] else { return nil } // notification
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return reply(id: id, result: [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "transkribe", "version": "1.0"],
                "instructions": "Tools to search and read the user's recorded conversations.",
            ])
        case "ping":
            return reply(id: id, result: [:])
        case "tools/list":
            return reply(id: id, result: ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let result = call(name, arguments: params["arguments"] as? [String: Any] ?? [:])
            return reply(id: id, result: ["content": [["type": "text", "text": result.text]], "isError": result.isError])
        default:
            return reply(id: id, error: (-32601, "Method not found: \(method)"))
        }
    }

    /// Serves stdin/stdout until the client closes the pipe.
    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, let response = handle(line: line) else { continue }
            FileHandle.standardOutput.write(Data((response + "\n").utf8))
        }
    }

    private func number(_ value: Any?) -> TimeInterval? {
        (value as? Double) ?? (value as? Int).map(Double.init)
    }

    private func reply(id: Any, result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func reply(id: Any, error: (Int, String)) -> String {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": error.0, "message": error.1]])
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
