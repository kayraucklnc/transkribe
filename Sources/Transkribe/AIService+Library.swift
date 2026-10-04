import Foundation
import TranskribeCore

/// One question to the whole library and how it was answered.
struct LibraryExchange: Identifiable, Equatable {
    let id = UUID()
    var question: String
    var answer = ""
    var steps: [String] = []
    var error: String?
    var isRunning = true
}

extension AIService {
    /// Answers a question across every conversation. Claude gets real tools (search, read, list)
    /// and looks things up itself; Apple's on-device model gets the best matching lines.
    func askLibrary(_ question: String, focus: Person? = nil, transcripts: [Transcript], people: [Person], userName: String?) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let provider = provider(for: selectedModel) else { return }
        let history = libraryExchanges.filter { $0.error == nil && !$0.isRunning }.flatMap {
            [AIMessage(role: .user, text: $0.question), AIMessage(role: .assistant, text: $0.answer)]
        }
        let messages = history + [AIMessage(role: .user, text: trimmed)]
        let library = ConversationLibrary(transcripts: transcripts, people: people)
        let system = LibraryAgent.system(userName: userName, focus: focus?.name)
        let model = selectedModel
        libraryExchanges.append(LibraryExchange(question: trimmed))
        let index = libraryExchanges.count - 1

        libraryTask?.cancel()
        libraryTask = Task {
            do {
                let events: AsyncThrowingStream<AgentEvent, Error>
                switch provider {
                case let claude as ClaudeCodeProvider:
                    events = claude.agent(model: model, system: system, messages: messages, mcpServer: Self.mcpServerURL)
                case let api as AnthropicAPIProvider:
                    let server = MCPServer(library: { library })
                    events = api.agent(model: model, system: system, messages: messages) { name, input in
                        server.call(name, arguments: input).text
                    }
                default:
                    events = Self.retrievalAnswer(provider: provider, model: model, system: system, question: trimmed,
                                                  messages: messages, library: library)
                }
                for try await event in events {
                    switch event {
                    case .text(let delta): libraryExchanges[index].answer += delta
                    case .resetText: libraryExchanges[index].answer = ""
                    case .toolCall(let name, let input):
                        libraryExchanges[index].steps.append(Self.describe(tool: name, input: input, transcripts: transcripts))
                    }
                }
            } catch is CancellationError {
            } catch {
                libraryExchanges[index].error = error.localizedDescription
            }
            libraryExchanges[index].isRunning = false
        }
    }

    func clearLibraryChat() {
        libraryTask?.cancel()
        libraryExchanges = []
    }

    /// The MCP server bundled next to the app's executable.
    static var mcpServerURL: URL {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("transkribe-mcp")
    }

    /// Small on-device models can't call tools well: give them the best matching lines instead.
    private static func retrievalAnswer(provider: any AIProvider, model: AIModel, system: String, question: String,
                                        messages: [AIMessage], library: ConversationLibrary) -> AsyncThrowingStream<AgentEvent, Error> {
        let budget = provider.contextCharacterBudget(for: model) - 1_500
        var context = library.search(query: question, limit: 20)
        let overview = library.listConversations(person: nil, limit: 8)
        if context.count + overview.count < budget { context += "\n\nRecent conversations:\n" + overview }
        let prompt = system + "\n\nYou can't call tools here; these are the lines that best match the question:\n" + String(context.prefix(max(500, budget)))
        let stream = provider.stream(model: model, system: prompt, messages: messages)
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.toolCall(name: "search_conversations", input: "{\"query\":\"\(question.prefix(40))\"}"))
                do {
                    for try await delta in stream { continuation.yield(.text(delta)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// "Searched “fiyat”", "Read Hakan bey 2:10–10:00", …
    static func describe(tool: String, input: String, transcripts: [Transcript]) -> String {
        let arguments = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any] ?? [:]
        switch tool {
        case "search_conversations":
            return "Searched “\(arguments["query"] as? String ?? "")”"
        case "read_conversation":
            let id = (arguments["id"] as? String).flatMap(UUID.init(uuidString:))
            let title = transcripts.first { $0.id == id }?.title ?? "a conversation"
            let from = (arguments["from"] as? Double) ?? (arguments["from"] as? Int).map(Double.init)
            let to = (arguments["to"] as? Double) ?? (arguments["to"] as? Int).map(Double.init)
            if let from, let to {
                return "Read “\(title)” \(TranscriptFormatter.timestamp(from))–\(TranscriptFormatter.timestamp(to))"
            }
            return "Read “\(title)”"
        case "list_conversations":
            return (arguments["person"] as? String).map { "Looked at conversations with \($0)" } ?? "Looked through your conversations"
        case "list_people":
            return "Looked at the people you talk with"
        default:
            return tool
        }
    }
}
