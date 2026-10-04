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
}
