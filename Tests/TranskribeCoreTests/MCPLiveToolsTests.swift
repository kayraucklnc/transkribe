import Foundation
import Testing
@testable import TranskribeCore

@Suite struct MCPLiveToolsTests {
    @Test(arguments: [101, Int.max])
    func conversationToolsClampLargeLimits(limit: Int) throws {
        let transcripts = (0..<101).map { index in
            Transcript(title: "Meeting \(index)", createdAt: Date(timeIntervalSince1970: Double(index)), tracks: [],
                segments: [.init(start: 0, end: 1, text: "Matching words")], status: .done)
        }
        let server = MCPServer(library: { ConversationLibrary(transcripts: transcripts, people: []) })
        let search = try rpcCall(server, "search_conversations", ["query": "Matching", "limit": limit])
        #expect(!search.isError)
        #expect(search.text.contains("showing 100,"))
        let list = try rpcCall(server, "list_conversations", ["limit": limit])
        #expect(!list.isError)
        #expect(list.text.split(separator: "\n").count == 100)
        #expect(try rpcCall(server, "search_conversations", ["query": "Matching"]).text.contains("showing 25,"))
        #expect(try rpcCall(server, "list_conversations", [:]).text.split(separator: "\n").count == 30)
    }

    @Test(arguments: [0, -1])
    func conversationToolsRejectNonpositiveLimits(limit: Int) throws {
        let transcript = Transcript(title: "Meeting", tracks: [],
            segments: [.init(start: 0, end: 1, text: "Matching words")], status: .done)
        let server = MCPServer(library: { ConversationLibrary(transcripts: [transcript], people: []) })
        for tool in ["search_conversations", "list_conversations"] {
            let result = try rpcCall(server, tool, ["query": "Matching", "limit": limit])
            #expect(result.isError)
            #expect(result.text == "The limit must be at least 1.")
        }
    }

    @Test func reconfiguringReadScopeKeepsActiveAnswerIDs() throws {
        let transcript = Transcript(title: "Live", tracks: [])
        let snapshots = { [MCPConversationSnapshot(transcript: transcript, isLive: true)] }
        let first = MCPLiveTools(snapshots: snapshots)
        let answer = try first.answerStore.post(conversationId: transcript.id, markdown: "First")
        let reconfigured = MCPLiveTools(snapshots: snapshots, readScopeDays: 1, answerStore: first.answerStore)
        let server = MCPServer(library: { ConversationLibrary(transcripts: [], people: []) }, extraTools: reconfigured.tools)
        let result = server.call("update_answer", arguments: ["answerId": answer.id.uuidString, "markdown": "Final", "final": true])
        #expect(!result.isError)
        #expect(first.answerStore.answers(for: transcript.id).first?.markdown == "Final")
    }

    @Test func extraToolsAreOptInAndCanReplaceAReadTool() throws {
        let library = { ConversationLibrary(transcripts: [], people: []) }
        let replacement = MCPTool(name: "read_conversation", description: "Read a current transcript.",
                                  properties: [:], required: []) { _, _ in ("Current text", false) }
        let extra = MCPTool(name: "extra", description: "Return an extra result.",
                            properties: [:], required: []) { _, _ in ("Extra text", false) }
        let normal = MCPServer(library: library)
        let extended = MCPServer(library: library, extraTools: [replacement, extra])
        let normalNames = try toolNames(normal)
        #expect(normalNames == ["search_conversations", "read_conversation", "list_conversations", "list_people"])
        #expect(normal.call("extra", arguments: [:]).isError)
        #expect(try toolNames(extended) == normalNames + ["extra"])
        #expect(extended.call("read_conversation", arguments: [:]).text == "Current text")
        #expect(extended.call("extra", arguments: [:]).text == "Extra text")
    }

    @Test func scopeFilterProtectsEveryLibraryToolAndExtraHandlers() {
        let visiblePerson = Person(name: "Visible Person")
        let hiddenPerson = Person(name: "Hidden Person", emails: ["hidden@example.test"])
        let thread = UUID()
        var visible = Transcript(title: "Visible meeting", tracks: [],
                                 segments: [.init(start: 0, end: 1, text: "Shared search words", speaker: 1)], status: .done)
        visible.speakerPeople = [1: visiblePerson.id]
        visible.threadID = thread
        var hidden = Transcript(title: "Hidden meeting", tracks: [],
                                segments: [.init(start: 0, end: 1, text: "Shared search words SECRET", speaker: 1)], status: .done)
        hidden.speakerPeople = [1: hiddenPerson.id]
        hidden.threadID = thread
        let library = { ConversationLibrary(transcripts: [visible, hidden], people: [visiblePerson, hiddenPerson]) }
        let extra = MCPTool(name: "extra", description: "List allowed conversations.", properties: [:], required: []) {
            _, library in (library.listConversations(person: nil), false)
        }
        let server = MCPServer(library: library, extraTools: [extra], scopeFilter: { $0.id == visible.id })
        let outputs = [
            server.call("list_conversations", arguments: [:]).text,
            server.call("search_conversations", arguments: ["query": "Shared search"]).text,
            server.call("read_conversation", arguments: ["id": visible.id.uuidString]).text,
            server.call("read_conversation", arguments: ["id": hidden.id.uuidString]).text,
            server.call("list_people", arguments: [:]).text,
            server.call("extra", arguments: [:]).text,
        ]
        for output in outputs {
            #expect(!output.contains("Hidden"))
            #expect(!output.contains("SECRET"))
            #expect(!output.contains("hidden@example.test"))
        }
        #expect(outputs[0].contains("Visible meeting"))
        #expect(outputs[4].contains("Visible Person"))
        #expect(MCPServer(library: library).call("list_people", arguments: [:]).text.contains("Hidden Person"))
    }

    @Test func liveReadsUseFreshSnapshotsIncludingPendingTextAndTimeRanges() throws {
        let time = Date(timeIntervalSince1970: 1_000_000)
        var current = Transcript(title: "Live meeting", createdAt: time.addingTimeInterval(-10 * 86_400), tracks: [],
                                 segments: [.init(start: 0, end: 2, text: "Committed words"),
                                            .init(start: 8, end: 10, text: "Pending words")], status: .transcribing)
        var disk = current
        disk.status = .done
        disk.segments = [.init(start: 0, end: 2, text: "Stale disk text")]
        let live = MCPLiveTools(snapshots: { [.init(transcript: current, isLive: true)] }, now: { time })
        let server = MCPServer(library: { ConversationLibrary(transcripts: [disk], people: []) },
                               extraTools: live.tools, scopeFilter: live.scopeFilter)
        let listed = server.call("list_live_conversations", arguments: [:])
        #expect(!listed.isError)
        #expect(listed.text.contains(current.id.uuidString))
        let read = server.call("read_conversation", arguments: ["id": current.id.uuidString])
        #expect(!read.isError)
        #expect(read.text.contains("Committed words"))
        #expect(read.text.contains("Pending words"))
        #expect(!read.text.contains("Stale disk text"))
        let section = server.call("read_conversation", arguments: ["id": current.id.uuidString, "from": 7, "to": 9])
        #expect(section.text.contains("Pending words"))
        #expect(!section.text.contains("Committed words"))
        current.segments.append(.init(start: 10, end: 12, text: "New words"))
        #expect(server.call("read_conversation", arguments: ["id": current.id.uuidString]).text.contains("New words"))
    }

    @Test func readScopeAllowsLiveAndOnlyRecentHistory() {
        var time = Date(timeIntervalSince1970: 2_000_000)
        let recent = Transcript(title: "Recent", createdAt: time.addingTimeInterval(-86_400), tracks: [], status: .done)
        let boundary = Transcript(title: "Boundary", createdAt: time.addingTimeInterval(-7 * 86_400), tracks: [], status: .done)
        let old = Transcript(title: "Excluded history", createdAt: time.addingTimeInterval(-8 * 86_400), tracks: [], status: .done)
        let liveTranscript = Transcript(title: "Long live meeting", createdAt: time.addingTimeInterval(-10 * 86_400), tracks: [], status: .transcribing)
        let snapshots = { [MCPConversationSnapshot(transcript: liveTranscript, isLive: true),
                           MCPConversationSnapshot(transcript: old, isLive: false, endedAt: old.createdAt)] }
        let library = { ConversationLibrary(transcripts: [recent, boundary, old], people: []) }
        let live = MCPLiveTools(snapshots: snapshots, now: { time })
        let server = MCPServer(library: library, extraTools: live.tools, scopeFilter: live.scopeFilter)
        for transcript in [recent, boundary, liveTranscript] {
            #expect(!server.call("read_conversation", arguments: ["id": transcript.id.uuidString]).isError)
        }
        #expect(server.call("read_conversation", arguments: ["id": old.id.uuidString]).isError)
        #expect(server.call("read_conversation", arguments: ["id": UUID().uuidString]).isError)
        #expect(!server.call("list_conversations", arguments: [:]).text.contains("Excluded history"))
        #expect(!server.call("list_live_conversations", arguments: [:]).text.contains("Excluded history"))
        let limited = MCPLiveTools(snapshots: snapshots, readScopeDays: 2, now: { time })
        let limitedServer = MCPServer(library: library, extraTools: limited.tools, scopeFilter: limited.scopeFilter)
        #expect(!limitedServer.call("read_conversation", arguments: ["id": recent.id.uuidString]).isError)
        #expect(limitedServer.call("read_conversation", arguments: ["id": boundary.id.uuidString]).isError)
        time.addTimeInterval(2 * 86_400)
        #expect(limitedServer.call("read_conversation", arguments: ["id": recent.id.uuidString]).isError)
        #expect(!limitedServer.call("read_conversation", arguments: ["id": liveTranscript.id.uuidString]).isError)
    }

    @Test func answerToolsPostReplaceAndFinalizeThroughJSONRPC() throws {
        let transcript = Transcript(title: "Live", tracks: [], status: .transcribing)
        let live = MCPLiveTools(snapshots: { [.init(transcript: transcript, isLive: true)] })
        let server = MCPServer(library: { ConversationLibrary(transcripts: [], people: []) },
                               extraTools: live.tools, scopeFilter: live.scopeFilter)
        let names = try toolNames(server)
        #expect(Set(names) == Set(["search_conversations", "read_conversation", "list_conversations", "list_people",
                                   "list_live_conversations", "post_answer", "update_answer"]))
        #expect(names.count == 7)
        let posted = try rpcCall(server, "post_answer", ["conversationId": transcript.id.uuidString, "markdown": "First take"])
        #expect(!posted.isError)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(posted.text.utf8)) as? [String: Any])
        let id = try #require(payload["answerId"] as? String)
        let uuid = try #require(UUID(uuidString: id))
        #expect(live.answerStore.answers(for: transcript.id).first?.markdown == "First take")
        let update = try rpcCall(server, "update_answer", ["answerId": id, "markdown": "Replacement", "final": false])
        #expect(!update.isError)
        #expect(live.answerStore.answers(for: transcript.id).first?.markdown == "Replacement")
        let final = try rpcCall(server, "update_answer", ["answerId": id, "markdown": "Final", "final": true])
        #expect(!final.isError)
        #expect(live.answerStore.answers(for: transcript.id).first?.id == uuid)
        #expect(live.answerStore.answers(for: transcript.id).first?.isFinal == true)
        let rejected = try rpcCall(server, "update_answer", ["answerId": id, "markdown": "Late", "final": false])
        #expect(rejected.isError)
        #expect(live.answerStore.answers(for: transcript.id).first?.markdown == "Final")
    }

    @Test func updateRequiresABooleanFinalFlag() throws {
        let transcript = Transcript(title: "Live", tracks: [])
        let live = MCPLiveTools(snapshots: { [.init(transcript: transcript, isLive: true)] })
        let server = MCPServer(library: { ConversationLibrary(transcripts: [], people: []) }, extraTools: live.tools)
        for invalid in [NSNull(), "true", 1, 0] as [Any] {
            let answer = try live.answerStore.post(conversationId: transcript.id, markdown: "Original")
            let result = try rpcCall(server, "update_answer", ["answerId": answer.id.uuidString,
                                                               "markdown": "Invalid", "final": invalid])
            #expect(result.isError)
            #expect(live.answerStore.answers(for: transcript.id).first { $0.id == answer.id } == answer)
        }
    }

    @Test func rejectedAnswersReturnToolErrors() throws {
        let time = Date(timeIntervalSince1970: 2_000_000)
        let transcript = Transcript(title: "Live", createdAt: time, tracks: [])
        var snapshot = MCPConversationSnapshot(transcript: transcript, isLive: true)
        let live = MCPLiveTools(snapshots: { [snapshot] }, now: { time })
        let server = MCPServer(library: { ConversationLibrary(transcripts: [], people: []) }, extraTools: live.tools)
        let unknown = UUID().uuidString
        #expect(try rpcCall(server, "post_answer", ["conversationId": unknown, "markdown": "Unknown"]).isError)
        #expect(try rpcCall(server, "update_answer", ["answerId": unknown, "markdown": "Unknown", "final": false]).isError)
        #expect(try rpcCall(server, "post_answer", [:]).isError)
        #expect(try rpcCall(server, "read_conversation", ["id": "invalid"]).isError)
        let answer = try live.answerStore.post(conversationId: transcript.id, markdown: "Original")
        let tooLarge = String(repeating: "x", count: 32_769)
        #expect(try rpcCall(server, "post_answer", ["conversationId": transcript.id.uuidString, "markdown": tooLarge]).isError)
        #expect(try rpcCall(server, "update_answer", ["answerId": answer.id.uuidString, "markdown": tooLarge, "final": false]).isError)
        for _ in 1...30 {
            #expect(try !rpcCall(server, "update_answer", ["answerId": answer.id.uuidString, "markdown": "Allowed", "final": false]).isError)
        }
        #expect(try rpcCall(server, "update_answer", ["answerId": answer.id.uuidString, "markdown": "Rate limited", "final": false]).isError)
        let other = try live.answerStore.post(conversationId: transcript.id, markdown: "Before expiry")
        snapshot.isLive = false
        snapshot.endedAt = time.addingTimeInterval(-86_400)
        #expect(try rpcCall(server, "post_answer", ["conversationId": transcript.id.uuidString, "markdown": "Expired"]).isError)
        #expect(try rpcCall(server, "update_answer", ["answerId": other.id.uuidString, "markdown": "Expired", "final": true]).isError)
        #expect(live.answerStore.answers(for: transcript.id).first { $0.id == other.id }?.markdown == "Before expiry")
    }

    private func rpcCall(_ server: MCPServer, _ name: String, _ arguments: [String: Any]) throws -> MCPToolResult {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                      "params": ["name": name, "arguments": arguments]]
        let data = try JSONSerialization.data(withJSONObject: request)
        let line = try #require(server.handle(line: String(decoding: data, as: UTF8.self)))
        let reply = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(reply["error"] == nil)
        let result = try #require(reply["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return (try #require(content.first?["text"] as? String), try #require(result["isError"] as? Bool))
    }

    private func toolNames(_ server: MCPServer) throws -> [String] {
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
        let reply = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let result = try #require(reply["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        return tools.compactMap { $0["name"] as? String }
    }
}
