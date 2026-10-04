import Foundation
import Testing
@testable import TranskribeCore

/// Runs the real model end to end. Downloads ~630 MB on first run, so it is opt-in:
/// `TRANSKRIBE_INTEGRATION=1 swift test --filter TranscriptionIntegrationTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_INTEGRATION"] == "1"), .serialized)
struct TranscriptionIntegrationTests {
    static let engine = TranscriptionEngine()
    static let diarizer = DiarizationEngine()

    private func speak(_ text: String, voice: String) throws -> URL {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("speech.aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", voice, "-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        return url
    }

    private func transcribe(_ url: URL) async throws -> TranscriptionEngine.Output {
        let samples = try await AudioDecoder.decode(url: url)
        return try await Self.engine.transcribe(samples: samples)
    }

    @Test func transcribesTurkish() async throws {
        let url = try speak("Merhaba, bugün hava çok güzel. Yarın İstanbul'a gidiyoruz.", voice: "Yelda")
        let output = try await transcribe(url)
        let text = TranscriptSearch.normalize(output.segments.map(\.text).joined(separator: " "))

        #expect(output.language == "tr")
        #expect(text.contains("merhaba"))
        #expect(text.contains("istanbul"))
    }

    @Test func transcribesItalian() async throws {
        let url = try speak("Buongiorno a tutti. Domani presentiamo il nuovo progetto al cliente di Milano.", voice: "Alice")
        let output = try await transcribe(url)
        let text = TranscriptSearch.normalize(output.segments.map(\.text).joined(separator: " "))

        #expect(output.language == "it")
        #expect(text.contains("buongiorno"))
        #expect(text.contains("milano"))
    }

    @Test func transcribesEnglish() async throws {
        let url = try speak("The quarterly report is due next Friday. Please send your numbers.", voice: "Samantha")
        let output = try await transcribe(url)
        let text = TranscriptSearch.normalize(output.segments.map(\.text).joined(separator: " "))

        #expect(output.language == "en")
        #expect(text.contains("quarterly report"))
        #expect(text.contains("friday"))
    }

    @Test func handlesLongAudioWithChunking() async throws {
        let sentences = [
            "Good morning everyone, thanks for joining the planning meeting.",
            "First, the mobile release slipped by one week because of the login bug.",
            "Maria will finish the payment screen before Wednesday.",
            "The design team shared new icons for the settings page.",
            "We still need a decision on the pricing for the enterprise plan.",
            "Customer support reported fewer tickets after the last update.",
            "Our database migration is scheduled for Saturday night.",
            "Please review the security checklist before you merge anything.",
            "Marketing wants a short demo video for the conference in May.",
            "The budget for new laptops was approved yesterday.",
            "Next week we will interview two candidates for the backend role.",
            "That is everything for today, see you all on Thursday.",
        ]
        let url = try speak(sentences.joined(separator: " "), voice: "Samantha")
        let output = try await transcribe(url)
        let text = TranscriptSearch.normalize(output.segments.map(\.text).joined(separator: " "))

        for keyword in ["planning meeting", "payment screen", "enterprise plan", "database migration", "conference", "thursday"] {
            #expect(text.contains(keyword), "missing \"\(keyword)\" in: \(text)")
        }
        #expect(output.segments.last!.end > 35)
        #expect(zip(output.segments, output.segments.dropFirst()).allSatisfy { $0.start <= $1.start })
    }

    @Test func separatesTwoSpeakers() async throws {
        let lines: [(String, String)] = [
            ("Samantha", "Hi Daniel, thanks for making time today. How did the customer visit go?"),
            ("Daniel", "It went really well. They loved the new dashboard and want to expand the contract next quarter."),
            ("Samantha", "That's great news. Did they mention anything about the pricing or the timeline?"),
            ("Daniel", "They asked for a discount on the annual plan, and they need the integration ready by March."),
            ("Samantha", "Okay, let's put together a proposal this week and review it on Friday."),
        ]
        var samples: [Float] = []
        for (voice, text) in lines {
            samples += try await AudioDecoder.decode(url: try speak(text, voice: voice))
            samples += [Float](repeating: 0, count: 8_000) // half a second of silence
        }

        let output = try await Self.engine.transcribe(samples: samples)
        let turns = try await Self.diarizer.turns(samples: samples)
        let labeled = SpeakerAssigner.assign(output.segments, turns: turns)
        print("TURNS:", turns.map { "\($0.speaker)@\(String(format: "%.1f", $0.start))" })
        print("LABELED:", labeled.map { "[\($0.speaker ?? -1)] \($0.text)" }.joined(separator: "\n"))

        #expect(Set(turns.map(\.speaker)).count == 2)
        let speakerOf = { (needle: String) in labeled.first { TranscriptSearch.normalize($0.text).contains(needle) }?.speaker }
        #expect(speakerOf("customer visit") == speakerOf("proposal"))
        #expect(speakerOf("dashboard") == speakerOf("annual plan"))
        #expect(speakerOf("customer visit") != speakerOf("dashboard"))
    }

    /// Two people at one Mac during a call: the main voice is "Me", the colleague gets their own label.
    @Test func microphoneKeepsSomeoneElseInTheRoomApart() async throws {
        let lines: [(String, String)] = [
            ("Daniel", "Okay, I'm sharing my screen now, can everyone see the quarterly numbers on the first slide?"),
            ("Samantha", "I'm sitting next to Daniel. The revenue line includes the two new enterprise customers from Germany."),
            ("Daniel", "Right, and the churn went down to two percent after we changed the onboarding flow in July."),
            ("Samantha", "We should also mention that support tickets dropped by almost a third since the redesign shipped."),
            ("Daniel", "Good point. Next slide shows the hiring plan, we want three engineers and one designer by December."),
            ("Samantha", "The designer role is the most urgent one, because the mobile app redesign starts in November."),
            ("Daniel", "Let's take questions now, and then we can go through the budget in more detail afterwards."),
            ("Samantha", "And I can send everyone the full spreadsheet after the call, including the regional breakdown."),
            ("Daniel", "Perfect, thank you. Who wants to start with a question about the numbers or the plan?"),
        ]
        var samples: [Float] = []
        for (voice, text) in lines {
            samples += try await AudioDecoder.decode(url: try speak(text, voice: voice))
            samples += [Float](repeating: 0, count: 8_000)
        }
        let output = try await Self.engine.transcribe(samples: samples)
        let turns = try await Self.diarizer.turns(samples: samples)
        let labeled = MicSpeakers.labelWithCall(output.segments, turns: turns)
        print("MIC:", labeled.map { "[\($0.speaker ?? -1)] \($0.text)" }.joined(separator: "\n"))

        let speakerOf = { (needle: String) in labeled.first { TranscriptSearch.normalize($0.text).contains(needle) }?.speaker }
        #expect(Set(labeled.compactMap(\.speaker)) == [SpeakerID.me, SpeakerID.firstInRoom])
        #expect(speakerOf("sharing my screen") == speakerOf("hiring plan"))
        #expect(speakerOf("sitting next to") == speakerOf("spreadsheet"))
        #expect(speakerOf("sharing my screen") != speakerOf("sitting next to"))
    }

    /// A voice note on the mic alone is just "Me".
    @Test func microphoneAloneWithOneVoiceIsMe() async throws {
        let samples = try await AudioDecoder.decode(url: try speak(
            "Reminder for tomorrow: call the accountant about the invoice, then book the flights to Milan for the conference.",
            voice: "Daniel"))
        let output = try await Self.engine.transcribe(samples: samples)
        let turns = try await Self.diarizer.turns(samples: samples)
        #expect(MicSpeakers.labelAlone(output.segments, turns: turns).allSatisfy { $0.speaker == SpeakerID.me })
    }

    @Test func honorsRequestedSpeakerCount() async throws {
        var samples: [Float] = []
        for (voice, text) in [("Samantha", "Let's review the plan for the launch next week."),
                              ("Daniel", "The payment integration is almost finished, maybe two more days."),
                              ("Samantha", "Great, and what about the onboarding screens?"),
                              ("Daniel", "Those are done. We can submit the beta on Friday.")] {
            samples += try await AudioDecoder.decode(url: try speak(text, voice: voice))
            samples += [Float](repeating: 0, count: 8_000)
        }
        let one = try await Self.diarizer.turns(samples: samples, speakerCount: 1)
        let two = try await Self.diarizer.turns(samples: samples, speakerCount: 2)
        #expect(Set(one.map(\.speaker)).count == 1)
        #expect(Set(two.map(\.speaker)).count == 2)
    }

    @Test func appleEngineTranscribesItalian() async throws {
        guard #available(macOS 26, *), AppleSpeechEngine.isAvailable else { return }
        let engine = AppleSpeechEngine(languages: ["it", "en"], vocabulary: ["Milano"])
        try await engine.prepare { _ in }
        let samples = try await AudioDecoder.decode(url: try speak("Buongiorno a tutti. Domani presentiamo il nuovo progetto al cliente di Milano.", voice: "Alice"))
        let output = try await engine.transcribe(samples: samples) { _ in }
        let text = TranscriptSearch.normalize(output.segments.map(\.text).joined(separator: " "))
        print("APPLE", output.language ?? "-", text)
        #expect(output.language == "it")
        #expect(text.contains("milano"))
        #expect(output.segments.allSatisfy { !$0.words.isEmpty })
    }

    @Test func parakeetHandlesItalianAndWhisperKeepsTurkish() async throws {
        let parakeet = ParakeetEngine()
        let engine = TranscriptionEngine(languages: ["tr", "it", "en"], european: parakeet)
        try await engine.prepare()
        let italian = try await AudioDecoder.decode(url: try speak("Buongiorno a tutti. Domani presentiamo il nuovo progetto al cliente di Milano.", voice: "Alice"))
        let it = try await engine.transcribe(samples: italian)
        let turkish = try await AudioDecoder.decode(url: try speak("Merhaba, bugün hava çok güzel. Yarın İstanbul'a gidiyoruz.", voice: "Yelda"))
        let tr = try await engine.transcribe(samples: turkish)
        print("PARAKEET it:", it.segments.map(\.text), "tr:", tr.segments.map(\.text))
        #expect(await parakeet.isReady)
        #expect(it.language == "it")
        #expect(TranscriptSearch.normalize(it.segments.map(\.text).joined()).contains("milano"))
        #expect(tr.language == "tr")
        #expect(TranscriptSearch.normalize(tr.segments.map(\.text).joined()).contains("istanbul"))
    }
}
