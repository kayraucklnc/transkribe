import Foundation

/// Read-only view of every conversation for an AI assistant: search lines, read parts of a
/// conversation, list conversations and people. Outputs are compact text meant for a model,
/// with ids it can pass back and timestamps it can cite.
public struct ConversationLibrary: Sendable {
    public let transcripts: [Transcript]
    public let people: [Person]

    public init(transcripts: [Transcript], people: [Person]) {
        self.transcripts = transcripts.filter { $0.status == .done }
        self.people = people
    }

    public static func load(store: TranscriptStore = TranscriptStore(rootDirectory: TranscriptStore.defaultRoot),
                            peopleStore: PeopleStore = PeopleStore()) -> ConversationLibrary {
        ConversationLibrary(transcripts: (try? store.loadAll()) ?? [], people: (try? peopleStore.load()) ?? [])
    }

    // MARK: - Tools

    public func search(query: String, limit: Int = 25) -> String {
        let terms = TranscriptSearch.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count > 1 }
        guard !terms.isEmpty else { return "Give a few words to search for." }
        let needed = max(1, (terms.count + 1) / 2)
        var hits: [(transcript: Transcript, segment: Segment, score: Int)] = []
        for transcript in transcripts {
            for segment in transcript.segments {
                let text = TranscriptSearch.normalize(segment.text)
                let score = terms.filter(text.contains).count
                if score >= needed { hits.append((transcript, segment, score)) }
            }
        }
        guard !hits.isEmpty else { return "No lines matched “\(query)”. Try other words, a synonym, or another language." }
        let best = hits.sorted { ($0.score, $0.transcript.createdAt) > ($1.score, $1.transcript.createdAt) }.prefix(limit)
        var output: [String] = ["\(hits.count) matching line\(hits.count == 1 ? "" : "s"); showing \(best.count), best first, grouped by conversation."]
        for transcript in transcripts where best.contains(where: { $0.transcript.id == transcript.id }) {
            output.append("")
            output.append(header(transcript))
            for hit in best where hit.transcript.id == transcript.id {
                output.append("  " + line(hit.segment, in: transcript))
            }
        }
        return output.joined(separator: "\n")
    }

    public func conversation(id: String, from: TimeInterval? = nil, to: TimeInterval? = nil, maxLines: Int = 200) -> String {
        guard let transcript = find(id) else { return "No conversation with id \(id). Use list_conversations or search_conversations to find ids." }
        var output = [details(transcript)]
        let lines = transcript.segments.filter { segment in
            (from.map { segment.end >= $0 } ?? true) && (to.map { segment.start <= $0 } ?? true)
        }
        if lines.isEmpty {
            output.append("No lines in that time range.")
        } else {
            output.append("Lines \(TranscriptFormatter.timestamp(lines[0].start))–\(TranscriptFormatter.timestamp(lines[lines.count - 1].end)):")
            output += lines.prefix(maxLines).map { line($0, in: transcript) }
            if lines.count > maxLines {
                let next = lines[maxLines].start
                output.append("… \(lines.count - maxLines) more lines. Call read_conversation with from=\(Int(next)) to continue.")
            }
        }
        return output.joined(separator: "\n")
    }

    public func listConversations(person: String?, limit: Int = 30) -> String {
        var list = transcripts.sorted { $0.createdAt > $1.createdAt }
        if let person, !person.isEmpty {
            let key = TranscriptSearch.normalize(person)
            list = list.filter { transcript in participants(of: transcript).contains { TranscriptSearch.normalize($0).contains(key) } }
        }
        guard !list.isEmpty else { return person.map { "No conversations with anyone called “\($0)”." } ?? "No conversations yet." }
        return list.prefix(limit).map { transcript in
            var text = "- " + header(transcript)
            if let gist = gist(transcript) { text += "\n  Summary: \(gist)" }
            return text
        }.joined(separator: "\n")
    }

    public func listPeople() -> String {
        guard !people.isEmpty else { return "No people saved yet. Speakers may still have names inside conversations." }
        return people.map { person in
            let together = transcripts.filter { $0.speakerPeople.values.contains(person.id) }.sorted { $0.createdAt > $1.createdAt }
            var text = "- \(person.name)"
            if !person.emails.isEmpty { text += " <\(person.emails.joined(separator: ", "))>" }
            text += " — \(together.count) conversation\(together.count == 1 ? "" : "s")"
            if let last = together.first { text += ", last \(Self.date(last.createdAt))" }
            return text
        }.joined(separator: "\n")
    }

    // MARK: - Formatting

    private func find(_ id: String) -> Transcript? {
        transcripts.first { $0.id.uuidString.caseInsensitiveCompare(id.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }

    func participants(of transcript: Transcript) -> [String] {
        let me = transcript.resolvedMeSpeaker
        let ordered = (me.map { [$0] } ?? []) + transcript.speakers.filter { $0 != me }
        return ordered.filter { transcript.speakers.contains($0) }.map { speaker in
            let name = transcript.name(of: speaker, people: people)
            return speaker == me ? (name == "Me" ? "Me (the user)" : "\(name) (the user)") : name
        }
    }

    private func kind(of transcript: Transcript) -> String {
        let count = transcript.speakers.count
        if count > 2 { return "group conversation (\(count) people)" }
        return count == 2 ? "one-to-one" : "single speaker"
    }

    private func header(_ transcript: Transcript) -> String {
        var parts = ["“\(transcript.title)” (id: \(transcript.id.uuidString))", Self.date(transcript.createdAt),
                     TranscriptFormatter.timestamp(transcript.duration) + " long"]
        let names = participants(of: transcript)
        if !names.isEmpty { parts.append("with " + names.joined(separator: ", ")) }
        parts.append(kind(of: transcript))
        if let part = partLabel(transcript) { parts.append(part) }
        return parts.joined(separator: " · ")
    }

    private func details(_ transcript: Transcript) -> String {
        var lines = ["“\(transcript.title)” (id: \(transcript.id.uuidString))",
                     "Recorded \(Self.date(transcript.createdAt)), \(TranscriptFormatter.timestamp(transcript.duration)) long" +
                        (Prompts.languageName(for: transcript.language).map { ", in \($0)" } ?? "")]
        lines.append("Participants: " + participants(of: transcript).joined(separator: ", "))
        lines.append("Kind: " + kind(of: transcript))
        if let thread = transcript.threadID {
            let sessions = Conversations.sessions(in: thread, from: transcripts)
            let index = (sessions.firstIndex { $0.id == transcript.id } ?? 0) + 1
            var text = "Part \(index) of \(sessions.count) of an ongoing conversation"
            let others = sessions.filter { $0.id != transcript.id }
            if !others.isEmpty {
                text += "; other parts: " + others.map { "\(Self.date($0.createdAt)) (id: \($0.id.uuidString))" }.joined(separator: ", ")
            }
            lines.append(text)
        }
        if let gist = gist(transcript) { lines.append("Summary: \(gist)") }
        return lines.joined(separator: "\n")
    }

    private func partLabel(_ transcript: Transcript) -> String? {
        guard let thread = transcript.threadID else { return nil }
        let sessions = Conversations.sessions(in: thread, from: transcripts)
        guard sessions.count > 1, let index = sessions.firstIndex(where: { $0.id == transcript.id }) else { return nil }
        return "part \(index + 1) of \(sessions.count) of an ongoing conversation"
    }

    private func line(_ segment: Segment, in transcript: Transcript) -> String {
        let name = segment.speaker.map { transcript.name(of: $0, people: people) }
        return "[\(TranscriptFormatter.timestamp(segment.start))] " + (name.map { "\($0): " } ?? "") + segment.text.trimmingCharacters(in: .whitespaces)
    }

    private func gist(_ transcript: Transcript) -> String? {
        guard let summary = transcript.summary?.markdown else { return nil }
        return summary.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        return formatter
    }()

    static func date(_ date: Date) -> String { formatter.string(from: date) }
}
