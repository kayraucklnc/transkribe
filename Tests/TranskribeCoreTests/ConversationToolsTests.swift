import Foundation
import Testing
@testable import TranskribeCore

@Suite struct ConversationToolsTests {
    let hakan = Person(name: "Hakan Yılmaz", emails: ["hakan@example.com"])
    let thread = UUID()

    private func library() -> ConversationLibrary {
        var call = Fixtures.transcript(title: "Hakan bey", segments: [
            Segment(start: 10, end: 14, text: "Fiyat sayfa başı ne kadar?", speaker: 1),
            Segment(start: 15, end: 20, text: "Sayfa başı yaklaşık iki yüz lira.", speaker: 0),
            Segment(start: 600, end: 604, text: "Pazartesi demo yapalım.", speaker: 1),
        ])
        call.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
        call.speakerPeople = [1: hakan.id]
        call.speakerNames = [1: "Hakan Yılmaz"]
        call.meSpeaker = 0
        call.threadID = thread
        var group = Fixtures.transcript(title: "Team sync", segments: [
            Segment(start: 0, end: 3, text: "Budget review today.", speaker: 1),
            Segment(start: 3, end: 6, text: "Pricing is the main topic.", speaker: 2),
            Segment(start: 6, end: 9, text: "Agreed.", speaker: 3),
        ])
        group.createdAt = Date(timeIntervalSince1970: 1_790_100_000)
        return ConversationLibrary(transcripts: [call, group], people: [hakan])
    }

    @Test func searchRanksLinesAcrossConversations() throws {
        let result = library().search(query: "fiyat sayfa")
        #expect(result.contains("Hakan bey"))
        #expect(result.contains("Fiyat sayfa başı ne kadar?"))
        #expect(result.contains("0:10"))
        #expect(!result.contains("Team sync"))
    }

    @Test func searchSaysWhenNothingMatches() {
        #expect(library().search(query: "zebra").contains("No lines"))
    }

    @Test func readsAConversationWithParticipantsAndTimeRange() throws {
        let lib = library()
        let id = lib.transcripts[0].id
        let text = lib.conversation(id: id.uuidString, from: 0, to: 60)
        #expect(text.contains("Participants: Me (the user), Hakan Yılmaz"))
        #expect(text.contains("[0:10] Hakan Yılmaz: Fiyat sayfa başı ne kadar?"))
        #expect(!text.contains("Pazartesi"))           // outside the range
        #expect(text.contains("Part 1 of"))
    }

    @Test func listsConversationsForAPersonAndMarksGroups() {
        let lib = library()
        let all = lib.listConversations(person: nil, limit: 10)
        #expect(all.contains("Team sync") && all.contains("group conversation"))
        let withHakan = lib.listConversations(person: "hakan", limit: 10)
        #expect(withHakan.contains("Hakan bey") && !withHakan.contains("Team sync"))
    }

    @Test func listsPeople() {
        let text = library().listPeople()
        #expect(text.contains("Hakan Yılmaz") && text.contains("hakan@example.com") && text.contains("1 conversation"))
    }
}

@Suite struct MCPServerTests {
    let server = MCPServer(library: { ConversationLibrary(transcripts: [], people: []) })

    private func send(_ json: String) throws -> [String: Any]? {
        guard let reply = server.handle(line: json) else { return nil }
        return try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any]
    }

    @Test func initializeAdvertisesTools() throws {
        let reply = try send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
        let result = reply?["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2025-06-18")
        #expect((result?["capabilities"] as? [String: Any])?["tools"] != nil)
    }

    @Test func notificationsGetNoReply() throws {
        #expect(try send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func listsTheFourTools() throws {
        let reply = try send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = (reply?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        #expect(Set(tools?.compactMap { $0["name"] as? String } ?? []) == ["search_conversations", "read_conversation", "list_conversations", "list_people"])
    }

    @Test func callsATool() throws {
        let reply = try send(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_conversations","arguments":{"query":"anything"}}}"#)
        let content = (reply?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        #expect((content?.first?["text"] as? String)?.contains("No lines") == true)
    }

    @Test func unknownMethodIsAnError() throws {
        let reply = try send(#"{"jsonrpc":"2.0","id":4,"method":"nope"}"#)
        #expect((reply?["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
}
