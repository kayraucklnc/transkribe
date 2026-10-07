import Foundation
import Testing
@testable import TranskribeCore

/// Builds a fictional library for screenshots and demos, voiced with macOS `say`:
/// `TRANSKRIBE_DEMO_HOME=/tmp/transkribe-demo swift test --filter DemoLibraryTests`,
/// then run the app with `TRANSKRIBE_HOME=/tmp/transkribe-demo`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_DEMO_HOME"] != nil), .serialized)
struct DemoLibraryTests {
    struct Line {
        var speaker: Int
        var text: String
    }

    struct Demo {
        var title: String
        var hoursAgo: Double
        var language: String
        var voices: [Int: String]
        var names: [Int: String]
        var me: Int?
        var people: [Int: String] = [:]
        var lines: [Line]
        var summary: String?
        var actionItems: [ActionItem]?
        var chat: [AIMessage]?
    }

    @Test func buildDemoLibrary() async throws {
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRANSKRIBE_DEMO_HOME"]!)
        let store = TranscriptStore(rootDirectory: home.appendingPathComponent("Library"))
        try? FileManager.default.removeItem(at: store.rootDirectory)

        let people = ["Maya Chen", "Daniel Okafor", "Ece Yılmaz", "Luca Bianchi"].map { Person(name: $0) }
        try PeopleStore(url: home.appendingPathComponent("people.json")).save(people)

        for demo in Self.demos {
            var transcript = Transcript(title: demo.title, createdAt: Date().addingTimeInterval(-demo.hoursAgo * 3_600),
                                        language: demo.language, tracks: [AudioTrack(fileName: "audio.wav")],
                                        status: .done, speakerNames: demo.names.merging(demo.people) { name, _ in name })
            let folder = try store.prepareDirectory(for: transcript)
            let (samples, segments) = try await voice(demo)
            try writeWAV(samples, to: folder.appendingPathComponent("audio.wav"))
            transcript.segments = segments
            transcript.duration = Double(samples.count) / AudioDecoder.sampleRate
            transcript.meSpeaker = demo.me
            transcript.quality = .best
            transcript.speakerPeople = demo.people.compactMapValues { name in people.first { $0.name == name }?.id }
            transcript.summary = demo.summary.map { AISummary(markdown: $0, modelName: "Claude Sonnet", createdAt: transcript.createdAt) }
            transcript.actionItems = demo.actionItems
            transcript.chat = demo.chat.map { AIChat(messages: $0, modelName: "Claude Sonnet") }
            try store.save(transcript)
        }
    }

    /// Speaks every line and lays them out one after another, with evenly spread word timings.
    private func voice(_ demo: Demo) async throws -> ([Float], [Segment]) {
        let gap = [Float](repeating: 0, count: Int(AudioDecoder.sampleRate * 0.35))
        var samples: [Float] = []
        var segments: [Segment] = []
        for line in demo.lines {
            let url = try Fixtures.temporaryDirectory().appendingPathComponent("line.aiff")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", demo.voices[line.speaker]!, "-o", url.path, line.text]
            try process.run()
            process.waitUntilExit()
            let spoken = try await AudioDecoder.decode(url: url)
            let start = Double(samples.count) / AudioDecoder.sampleRate
            let end = start + Double(spoken.count) / AudioDecoder.sampleRate
            let tokens = line.text.split(separator: " ").map(String.init)
            let step = (end - start) / Double(tokens.count)
            let words = tokens.enumerated().map { index, token in
                Word(start: start + Double(index) * step, end: start + Double(index + 1) * step, text: " " + token)
            }
            segments.append(Segment(start: start, end: end, text: line.text, speaker: line.speaker, words: words))
            samples += spoken + gap
        }
        return (samples, segments)
    }

    /// 16-bit mono PCM at the decoder's sample rate.
    private func writeWAV(_ samples: [Float], to url: URL) throws {
        let rate = UInt32(AudioDecoder.sampleRate)
        let pcm = samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + pcm.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(rate); append(rate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(pcm.count * 2))
        pcm.forEach { append($0) }
        try data.write(to: url)
    }

    static let demos: [Demo] = [launchSync, kahve, chiamata, podcast]

    static let launchSync = Demo(
        title: "Q4 launch sync",
        hoursAgo: 2,
        language: "en",
        voices: [1: "Samantha", 2: "Daniel", 3: "Karen"],
        names: [:],
        me: 1,
        people: [2: "Daniel Okafor", 3: "Maya Chen"],
        lines: [
            Line(speaker: 1, text: "Okay, let's get started. The main thing today is whether we still ship the new onboarding on November twelfth."),
            Line(speaker: 3, text: "Design is done. The last screens went to engineering on Monday, so nothing is blocked on our side."),
            Line(speaker: 2, text: "Engineering is about eighty percent there. The risky part is the account migration for existing users."),
            Line(speaker: 1, text: "How risky are we talking? Is it a week of work or something we don't fully understand yet?"),
            Line(speaker: 2, text: "Honestly, a bit of both. The happy path works, but about two percent of accounts have old settings that break the import."),
            Line(speaker: 3, text: "Could we ship onboarding for new users first, and migrate existing accounts a week later?"),
            Line(speaker: 1, text: "Yeah."),
            Line(speaker: 2, text: "That would work. New users don't touch the migration at all, so the twelfth is realistic for them."),
            Line(speaker: 1, text: "I like that. Let's split the launch. New users on the twelfth, existing accounts on the nineteenth."),
            Line(speaker: 3, text: "Perfect."),
            Line(speaker: 3, text: "Then I'll update the launch post and the help center so they only mention new accounts at first."),
            Line(speaker: 2, text: "And I'll write a script that finds the broken accounts, so we know exactly how many there are by Friday."),
            Line(speaker: 1, text: "Great. One more thing. Support asked for a heads up before anything goes live. Who can brief them?"),
            Line(speaker: 3, text: "I can do it. I'm meeting their lead on Thursday anyway."),
            Line(speaker: 1, text: "Perfect. Last question, do we still want the press embargo, or is that overkill for a split launch?"),
            Line(speaker: 2, text: "Haha."),
            Line(speaker: 2, text: "I'd skip it. Let's keep the big announcement for when everyone has it."),
            Line(speaker: 1, text: "Fair. Let's decide that next week once we've seen the numbers. Thanks everyone."),
        ],
        summary: """
        ## TL;DR
        The team agreed to split the onboarding launch: new users get it on November 12, existing accounts a week later once the account migration is fixed.

        ## Key points
        - Design is finished; engineering is about 80% done.
        - About 2% of existing accounts have old settings that break the migration.
        - New users don't go through the migration, so November 12 is realistic for them.

        ## Decisions
        - Launch for new users on November 12 and for existing accounts on November 19 [0:44]

        ## Action items
        - [ ] Maya Chen — Update the launch post and help center to mention new accounts only
        - [ ] Daniel Okafor — Write a script that finds the broken accounts (due: Friday) [0:56]
        - [ ] Maya Chen — Brief the support team (due: Thursday)

        ## Open questions
        - Whether to keep the press embargo, to be decided next week.

        ## Who said what
        - **Me** — ran the meeting and proposed the final dates
        - **Maya Chen** — design lead; suggested splitting the launch
        - **Daniel Okafor** — engineering; flagged the migration risk
        """,
        actionItems: [
            ActionItem(task: "Update the launch post and help center", owner: "Maya Chen", due: "before launch", time: 51),
            ActionItem(task: "Write a script that finds the broken accounts", owner: "Daniel Okafor", due: "Friday", time: 56),
            ActionItem(task: "Brief the support team before go-live", owner: "Maya Chen", due: "Thursday", time: 69),
            ActionItem(task: "Decide on the press embargo", owner: "Me", due: "next week", time: 84),
        ],
        chat: [
            AIMessage(role: .user, text: "Why did we move existing accounts to the 19th?"),
            AIMessage(role: .assistant, text: "Because about **2% of existing accounts** have old settings that break the import [0:24]. New users never go through the migration, so Maya suggested shipping to them first and migrating everyone else a week later [0:33]."),
        ]
    )

    static let kahve = Demo(
        title: "Ece ile kahve",
        hoursAgo: 27,
        language: "tr",
        voices: [1: "Yelda", 2: "Yelda"],
        names: [:],
        me: 1,
        people: [2: "Ece Yılmaz"],
        lines: [
            Line(speaker: 2, text: "Selam! Nasıl gidiyor yeni proje?"),
            Line(speaker: 1, text: "İyi gidiyor aslında. Bu hafta ilk sürümü ekibe gösterdik."),
            Line(speaker: 2, text: "Vay be!"),
            Line(speaker: 2, text: "Tepkiler nasıldı peki?"),
            Line(speaker: 1, text: "Çoğu çok beğendi. Sadece arama biraz yavaş dediler, onu düzelteceğim."),
            Line(speaker: 2, text: "Cumartesi İstanbul'a geliyorum bu arada. Bir kahve içelim mi?"),
            Line(speaker: 1, text: "Tabii, Kadıköy'de buluşalım. Saat iki uyar mı?"),
            Line(speaker: 2, text: "Tamam."),
            Line(speaker: 2, text: "Harika, görüşürüz o zaman!"),
        ]
    )

    static let chiamata = Demo(
        title: "Chiamata con Luca",
        hoursAgo: 51,
        language: "it",
        voices: [1: "Alice", 2: "Eddy (Italian (Italy))"],
        names: [:],
        me: 1,
        people: [2: "Luca Bianchi"],
        lines: [
            Line(speaker: 2, text: "Ciao! Hai visto la proposta che ti ho mandato ieri sera?"),
            Line(speaker: 1, text: "Sì, l'ho letta stamattina. Mi piace molto, soprattutto la parte sul prezzo."),
            Line(speaker: 2, text: "Perfetto."),
            Line(speaker: 2, text: "Allora possiamo presentarla al cliente di Milano la settimana prossima?"),
            Line(speaker: 1, text: "Direi di sì. Preparo io le slide entro giovedì."),
            Line(speaker: 2, text: "Ottimo, ci sentiamo venerdì per una prova."),
        ]
    )

    static let podcast = Demo(
        title: "Local-first software, episode 42",
        hoursAgo: 75,
        language: "en",
        voices: [1: "Moira", 2: "Rishi"],
        names: [1: "Host", 2: "Guest"],
        me: nil,
        lines: [
            Line(speaker: 1, text: "Welcome back to the show. Today we're talking about apps that keep your data on your own device."),
            Line(speaker: 2, text: "Thanks for having me. I think the big shift is that laptops are now fast enough to run models that used to need a data center."),
            Line(speaker: 1, text: "So speech recognition, for example, can just run on a Mac?"),
            Line(speaker: 2, text: "Exactly. And once it runs locally, privacy stops being a trade-off. Your recordings simply never leave the machine."),
        ]
    )
}
