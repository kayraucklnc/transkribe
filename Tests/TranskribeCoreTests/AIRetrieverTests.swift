import Foundation
import Testing
@testable import TranskribeCore

@Suite struct AIRetrieverTests {
    private let chunks = [
        "[0:00] Ali: Günaydın, herkes burada mı?",
        "[1:00] Ayşe: Bütçeyi gözden geçirdim, pazarlama bütçesi yüzde on arttı.",
        "[2:00] Ali: Hava çok güzel bugün.",
        "[3:00] Mehmet: Lansman tarihi Mart ayına kaydı.",
        "[4:00] Ali: Yemek nerede yiyelim?",
    ]

    @Test func findsTurkishInflectionsIgnoringDiacriticsAndCase() {
        // "butce" (no diacritics) must match "Bütçeyi" and "bütçesi".
        let picked = TranscriptRetriever.retrieve(question: "BUTCE ne kadar arttı?", from: chunks, budget: chunks[1].count)
        #expect(picked == [chunks[1]])
    }

    @Test func handlesDotlessAndDottedI() {
        let chunks = ["[0:00] İstanbul ofisi kapanıyor.", "[1:00] Ankara ofisi büyüyor."]
        #expect(TranscriptRetriever.retrieve(question: "istanbul", from: chunks, budget: chunks[0].count) == [chunks[0]])
        #expect(TranscriptRetriever.retrieve(question: "ISTANBUL'DA ne oldu", from: chunks, budget: chunks[0].count) == [chunks[0]])
    }

    @Test func returnsBestChunksInOriginalOrderWithinBudget() {
        let budget = chunks[1].count + chunks[3].count + 1
        let picked = TranscriptRetriever.retrieve(question: "Lansman tarihi ve bütçe?", from: chunks, budget: budget)
        #expect(picked == [chunks[1], chunks[3]])
        #expect(picked.joined(separator: "\n").count <= budget)
    }

    @Test func prefersNeighborsOfHitsOverUnrelatedChunks() {
        let budget = chunks[3].count + chunks[2].count + 1
        let picked = TranscriptRetriever.retrieve(question: "lansman", from: chunks, budget: budget)
        #expect(picked.contains(chunks[3]))
        #expect(picked.count == 2)
        #expect(!picked.contains(chunks[0]))
    }

    @Test func ignoresStopWords() {
        #expect(TranscriptRetriever.keywords(in: "What did they say about the price?") == ["price"])
        #expect(TranscriptRetriever.keywords(in: "Toplantıda ne dedi, bu konu için?") == ["toplantida", "konu"])
        #expect(TranscriptRetriever.keywords(in: "Q3 rakamları") == ["q3", "rakamlari"])
    }

    @Test func matchesEnglishInflections() {
        #expect(TranscriptRetriever.matches(word: "pricing", term: "price"))
        #expect(TranscriptRetriever.matches(word: "launched", term: "launch"))
        #expect(!TranscriptRetriever.matches(word: "car", term: "cat"))
    }

    @Test func spreadsAcrossTranscriptWhenNothingMatches() {
        let chunks = (0..<9).map { "chunk \($0) filler" }
        // 14 + 15 + 15 characters (two joining newlines): room for exactly three chunks.
        let picked = TranscriptRetriever.retrieve(question: "zzz", from: chunks, budget: 3 * 15)
        #expect(picked == [chunks[0], chunks[4], chunks[8]])
    }

    @Test func excerptsMarkGaps() {
        let segments = (0..<60).map { index in
            Segment(start: Double(index) * 60, end: Double(index) * 60 + 5,
                    text: index == 30 ? "The secret launch code is falcon." : "Routine status update number \(index).",
                    speaker: index % 2 + 1)
        }
        let transcript = Fixtures.transcript(segments: segments)
        let excerpts = TranscriptRetriever.excerpts(for: "What is the launch code?", in: transcript, budget: 600)
        #expect(excerpts.contains("falcon"))
        #expect(excerpts.count <= 600 + 20)
        #expect(excerpts.contains(TranscriptRetriever.gapMarker))
    }

    @Test func emptyInputs() {
        #expect(TranscriptRetriever.retrieve(question: "x", from: [], budget: 100).isEmpty)
        #expect(TranscriptRetriever.retrieve(question: "bütçe", from: chunks, budget: 0).isEmpty)
    }
}
