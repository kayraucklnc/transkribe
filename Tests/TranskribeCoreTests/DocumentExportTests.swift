import Foundation
import Testing
@testable import TranskribeCore

@Suite struct DocumentExportTests {
    private func sample() -> (Transcript, [Person]) {
        let hakan = Person(name: "Hakan Yılmaz")
        var transcript = Fixtures.transcript(segments: [
            Segment(start: 0, end: 4, text: "Merhaba Hakan bey.", speaker: SpeakerID.me),
            Segment(start: 4, end: 9, text: "Merhaba, buyurun.", speaker: 1),
            Segment(start: 9, end: 12, text: "Fiyatı konuşalım.", speaker: 1),
        ])
        transcript.title = "Hakan bey"
        transcript.speakerPeople = [1: hakan.id]
        transcript.summary = AISummary(markdown: "## Özet\nFiyat konuşuldu.", modelName: "Claude")
        var item = ActionItem(task: "Teklif gönder", owner: "Me", due: "Cuma", time: 9)
        item.isDone = true
        transcript.actionItems = [item]
        return (transcript, [hakan])
    }

    @Test func markdownHasSummaryToDosAndTheConversationWithRealNames() {
        let (transcript, people) = sample()
        let markdown = DocumentExport.markdown(transcript, people: people)
        #expect(markdown.hasPrefix("# Hakan bey\n"))
        #expect(markdown.contains("Me, Hakan Yılmaz"))
        #expect(markdown.contains("## Özet\nFiyat konuşuldu."))
        #expect(markdown.contains("- [x] Teklif gönder — Me (Cuma)"))
        #expect(markdown.contains("**Hakan Yılmaz** · 0:04\nMerhaba, buyurun. Fiyatı konuşalım."))
    }

    @Test func htmlEscapesTextAndKeepsStructure() {
        var (transcript, people) = sample()
        transcript.segments[0].text = "<script>x</script> & more"
        let html = DocumentExport.html(transcript, people: people)
        #expect(html.contains("&lt;script&gt;x&lt;/script&gt; &amp; more"))
        #expect(html.contains("<h1>Hakan bey</h1>"))
        #expect(!html.contains("<script>"))
    }
}
