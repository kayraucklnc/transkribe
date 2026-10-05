import Foundation

/// Runs models through the user's locally signed-in Claude Code CLI (`claude -p`), so no API key is needed.
public struct ClaudeCodeProvider: AIProvider {
    public static let opus = AIModel(provider: .claudeCode, id: "opus", displayName: "Claude Opus (Claude Code)")
    public static let sonnet = AIModel(provider: .claudeCode, id: "sonnet", displayName: "Claude Sonnet (Claude Code)")
    public static let haiku = AIModel(provider: .claudeCode, id: "haiku", displayName: "Claude Haiku (Claude Code)")

    static let notInstalledReason = "Install Claude Code and sign in with `claude`."
    /// Variables that would make the child think it runs inside another Claude Code session.
    static let removedEnvironmentKeys = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION"]
    /// Above this many bytes the system prompt goes in a temporary file instead of argv (ARG_MAX is 1 MB).
    static let maxInlineSystemPromptBytes = 100_000

    public let kind = AIProviderKind.claudeCode
    public var models: [AIModel] { [Self.opus, Self.sonnet, Self.haiku] }

    private let executableURL: URL?

    /// - Parameter executableURL: a specific `claude` binary; found automatically when nil.
    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL
    }

    public func contextCharacterBudget(for model: AIModel) -> Int {
        // Haiku has a 200K-token window; the others 1M (Claude Code may cap lower, so stay conservative).
        model.id == Self.haiku.id ? 500_000 : 600_000
    }

    public func availability() async -> AIAvailability {
        let explicit = executableURL
        let found = await Task.detached { explicit ?? Self.locateExecutable() }.value
        return found == nil ? .unavailable(reason: Self.notInstalledReason) : .available
    }

    public func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        let explicit = executableURL
        let run = ClaudeCodeRun()
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    guard let executable = explicit ?? Self.locateExecutable() else {
                        throw AIError(Self.notInstalledReason)
                    }
                    let input = Data(ConversationRenderer.prompt(from: messages).utf8)
                    try await run.run(executable: executable, model: model.id, system: system, input: input) { delta in
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                run.terminate()
            }
        }
    }

    /// Runs Claude with the conversation tools of an MCP server, reporting tool calls as they
    /// happen. Text written before a tool call is withdrawn (`.resetText`); only the final answer stays.
    public func agent(model: AIModel, system: String, messages: [AIMessage], mcpServer: URL) -> AsyncThrowingStream<AgentEvent, Error> {
        let explicit = executableURL
        let run = ClaudeCodeRun()
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                let config = FileManager.default.temporaryDirectory.appendingPathComponent("transkribe-mcp-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: config) }
                do {
                    guard let executable = explicit ?? Self.locateExecutable() else { throw AIError(Self.notInstalledReason) }
                    let servers = ["mcpServers": ["transkribe": ["type": "stdio", "command": mcpServer.path, "args": [String]()]]]
                    try JSONSerialization.data(withJSONObject: servers).write(to: config)
                    let allowed = MCPServer.tools.compactMap { $0["name"] as? String }.map { "mcp__transkribe__\($0)" }
                    let input = Data(ConversationRenderer.prompt(from: messages).utf8)
                    try await run.run(executable: executable, model: model.id, system: system, input: input,
                                      extraArguments: ["--mcp-config", config.path, "--allowedTools", allowed.joined(separator: ",")],
                                      onTool: { name, input in
                                          continuation.yield(.resetText)
                                          continuation.yield(.toolCall(name: name.replacingOccurrences(of: "mcp__transkribe__", with: ""), input: input))
                                      },
                                      onDelta: { continuation.yield(.text($0)) })
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                run.terminate()
            }
        }
    }

    // MARK: - Process setup

    static func arguments(model: String, system: SystemPromptArgument) -> [String] {
        let systemArguments: [String]
        switch system {
        case .inline(let text): systemArguments = ["--system-prompt", text]
        case .file(let url): systemArguments = ["--system-prompt-file", url.path]
        }
        return ["-p", "--model", model, "--tools", ""] + systemArguments + [
            "--output-format", "stream-json", "--include-partial-messages", "--verbose",
            "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config",
        ]
    }

    enum SystemPromptArgument: Equatable {
        case inline(String)
        case file(URL)
    }

    static func environment(from base: [String: String], executable: URL) -> [String: String] {
        var environment = base
        for key in removedEnvironmentKeys { environment.removeValue(forKey: key) }
        // Apps launched from Finder get a minimal PATH; `claude` may need node or its own bin dir.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = [executable.deletingLastPathComponent().path, "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let current = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        environment["PATH"] = (current + extra.filter { !current.contains($0) }).joined(separator: ":")
        return environment
    }

    /// Finds the `claude` binary in the usual install locations, then via a login shell.
    public static func locateExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }
        return pathFromLoginShell()
    }

    private static func pathFromLoginShell() -> URL? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A broken shell profile must not hang the app.
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        let path = String(decoding: data, as: UTF8.self)
            .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard process.terminationStatus == 0, path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Turns a Claude Code error result into something a user can act on.
    static func friendlyMessage(forResult message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("/login") || lowered.contains("not logged in") || lowered.contains("invalid api key")
            || lowered.contains("authenticat") || lowered.contains("oauth") {
            return "Claude Code isn't signed in. Run `claude` in Terminal and sign in, then try again."
        }
        if lowered.contains("usage limit") || lowered.contains("rate limit") {
            return "Claude Code reached its usage limit. Try again later or pick another model."
        }
        return "Claude Code: \(message)"
    }
}

/// Parses `claude -p --output-format stream-json --include-partial-messages` output lines.
public enum ClaudeCodeStreamParser {
    public enum Event: Equatable, Sendable {
        case textDelta(String)
        /// The model called a tool (MCP tools appear as `mcp__server__tool`).
        case toolUse(name: String, input: String)
        /// The final line. `text` is the full reply on success, the error message on failure.
        case result(text: String?, isError: Bool)
    }

    public static func parse(line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .textDelta(text)
        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]],
                  let call = content.first(where: { $0["type"] as? String == "tool_use" }),
                  let name = call["name"] as? String else { return nil }
            let input = (call["input"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            return .toolUse(name: name, input: input)
        case "result":
            let isError = object["is_error"] as? Bool ?? false
            var text = object["result"] as? String
            if isError, text?.isEmpty ?? true {
                text = (object["errors"] as? [String])?.joined(separator: "\n") ?? (object["subtype"] as? String)
            }
            return .result(text: text, isError: isError)
        default:
            return nil
        }
    }
}

/// One `claude -p` invocation. Thread-safe so the stream's termination handler can stop it.
final class ClaudeCodeRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func run(executable: URL, model: String, system: String, input: Data, extraArguments: [String] = [],
             onTool: (String, String) -> Void = { _, _ in }, onDelta: (String) -> Void) async throws {
        var systemFile: URL?
        defer { systemFile.map { try? FileManager.default.removeItem(at: $0) } }
        let systemArgument: ClaudeCodeProvider.SystemPromptArgument
        if system.utf8.count > ClaudeCodeProvider.maxInlineSystemPromptBytes {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("transkribe-system-\(UUID().uuidString).txt")
            try Data(system.utf8).write(to: url, options: .atomic)
            systemFile = url
            systemArgument = .file(url)
        } else {
            systemArgument = .inline(system)
        }

        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable
        process.arguments = ClaudeCodeProvider.arguments(model: model, system: systemArgument) + extraArguments
        process.environment = ClaudeCodeProvider.environment(from: ProcessInfo.processInfo.environment, executable: executable)
        // Keep the CLI away from any project's CLAUDE.md.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try start(process)

        // Writing to a pipe whose reader died must fail with EPIPE, not kill the app with SIGPIPE.
        let writer = stdin.fileHandleForWriting
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }
        let errorReader = stderr.fileHandleForReading
        let errorOutput = Task.detached { errorReader.readDataToEndOfFile() }

        var sawDelta = false
        var finalText: String?
        var errorMessage: String?
        do {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                switch ClaudeCodeStreamParser.parse(line: line) {
                case .textDelta(let text):
                    sawDelta = true
                    onDelta(text)
                case .toolUse(let name, let input):
                    onTool(name, input)
                case .result(let text, let isError):
                    if isError { errorMessage = text ?? "Unknown error" } else { finalText = text }
                case nil:
                    continue
                }
            }
        } catch {
            terminate()
            throw error
        }
        process.waitUntilExit()
        let stderrText = String(decoding: await errorOutput.value, as: UTF8.self)

        if isCancelled || Task.isCancelled { throw CancellationError() }
        if let errorMessage {
            throw AIError(ClaudeCodeProvider.friendlyMessage(forResult: errorMessage))
        }
        if !sawDelta, let finalText, !finalText.isEmpty {
            onDelta(finalText)
            sawDelta = true
        }
        if process.terminationStatus != 0, !sawDelta {
            let detail = stderrText.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500)
            throw AIError(detail.isEmpty
                ? "Claude Code stopped unexpectedly (exit code \(process.terminationStatus))."
                : ClaudeCodeProvider.friendlyMessage(forResult: String(detail)))
        }
    }

    private func start(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        do {
            try process.run()
        } catch {
            throw AIError("Couldn't start Claude Code: \(error.localizedDescription)")
        }
        self.process = process
    }
}
