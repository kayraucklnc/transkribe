import Foundation
import Testing
@testable import TranskribeCore

@Suite struct MeaningSearchTests {
    @Test func readsTermsFromTheModel() {
        #expect(MeaningSearch.parseTerms(#"["fiyat", "Ücret", "price", "fiyat"]"#, query: "money") == ["money", "fiyat", "ücret", "price"])
        #expect(MeaningSearch.parseTerms("Sure: fiyat, ücret\n- price", query: "money") == ["money", "fiyat", "ücret", "price"])
    }

    @Test func findsLinesWithAnyTermAndRanksConversations() {
        let a = Fixtures.transcript(segments: [
            Segment(start: 0, end: 2, text: "Fiyatlar nasıl?"),
            Segment(start: 5, end: 8, text: "Ücret sayfa başı 200 lira."),
            Segment(start: 9, end: 10, text: "Tamam."),
        ])
        let b = Fixtures.transcript(segments: [Segment(start: 0, end: 2, text: "The price is fine.")])
        let c = Fixtures.transcript(segments: [Segment(start: 0, end: 2, text: "Let's go hiking.")])
        let terms = ["money", "fiyat", "ücret", "price"]
        #expect(MeaningSearch.hits(in: a, terms: terms).map(\.start) == [0, 5])
        #expect(MeaningSearch.rank([c, b, a], terms: terms).map(\.id) == [a.id, b.id])
    }

    @Test func termsMatchAtTheStartOfWords() {
        #expect(MeaningSearch.matches("fiyat", in: "bu fiyatı uygun"))
        #expect(!MeaningSearch.matches("pay", in: "yapay zeka"))
        #expect(MeaningSearch.matches("how much", in: "so how much is it"))
    }

    @Test func promptAsksForTheUsersLanguages() {
        let prompt = MeaningSearch.system(languages: ["tr", "it"])
        #expect(prompt.contains("Turkish") && prompt.contains("Italian"))
    }
}
