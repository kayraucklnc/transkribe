import SwiftUI
import TranskribeCore
import UniformTypeIdentifiers

struct TranscriptView: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model
    @Environment(PlayerController.self) private var player
    @State private var title = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    status
                    segments
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            if !transcript.tracks.isEmpty {
                Divider()
                PlayerBar()
            }
        }
        .navigationTitle("")
        .toolbar { toolbar }
        .task(id: transcript.id) {
            title = transcript.title
            await player.load(transcript, store: model.store)
        }
        .onChange(of: transcript.title) { _, newValue in title = newValue }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .semibold))
                .onSubmit { model.rename(transcript.id, to: title) }
            Text(details)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 22)
    }

    private var details: String {
        var parts = [
            transcript.createdAt.formatted(date: .abbreviated, time: .shortened),
            TranscriptFormatter.timestamp(transcript.duration),
        ]
        if let code = transcript.language, let name = Locale.current.localizedString(forLanguageCode: code) {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        switch transcript.status {
        case .pending:
            StatusBanner(text: "Waiting to transcribe…", progress: nil)
        case .transcribing:
            StatusBanner(text: "Transcribing…", progress: model.progress[transcript.id])
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Try Again") { model.retry(transcript.id) }
            }
            .padding(.bottom, 20)
        case .done:
            if transcript.segments.isEmpty {
                Text("No speech was found in this audio.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var segments: some View {
        let matches = TranscriptSearch.matchingSegmentIDs(in: transcript, query: model.query)
        let paragraphs = ParagraphBuilder.paragraphs(from: transcript.segments)
        let current = paragraphs.last { $0.start <= player.currentTime }?.id
        return ForEach(Array(paragraphs.enumerated()), id: \.element.id) { index, paragraph in
            let previous = index > 0 ? paragraphs[index - 1].speaker : nil
            ParagraphRow(
                paragraph: paragraph,
                showsSpeaker: paragraph.speaker != nil && (index == 0 || paragraph.speaker != previous),
                isCurrent: player.isPlaying && paragraph.id == current,
                isMatch: paragraph.segmentIDs.contains(where: matches.contains),
                onPlay: { player.play(from: paragraph.start) }
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.copyText(of: transcript.id)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy transcript (⇧⌘C)")
            .disabled(transcript.segments.isEmpty)

            Menu {
                Button("Text (.txt)") { export(.plainText) }
                Button("Markdown (.md)") { export(.markdown) }
                Button("Subtitles (.srt)") { export(.srt) }
                Divider()
                Button("Show in Finder") { model.revealInFinder(transcript.id) }
                Button("Delete", role: .destructive) { model.delete(transcript.id) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export or manage this transcript")
        }
    }

    private enum ExportFormat {
        case plainText, markdown, srt

        var fileExtension: String {
            switch self {
            case .plainText: "txt"
            case .markdown: "md"
            case .srt: "srt"
            }
        }
    }

    private func export(_ format: ExportFormat) {
        let text = switch format {
        case .plainText: TranscriptFormatter.plainText(transcript)
        case .markdown: TranscriptFormatter.markdown(transcript)
        case .srt: TranscriptFormatter.srt(transcript)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(transcript.title).\(format.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.alert = .init(message: "Couldn't save the file. \(error.localizedDescription)")
        }
    }
}

private struct StatusBanner: View {
    let text: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text)
                Spacer()
                if let progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: progress)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.bottom, 20)
    }
}

private struct ParagraphRow: View {
    let paragraph: Paragraph
    let showsSpeaker: Bool
    let isCurrent: Bool
    let isMatch: Bool
    let onPlay: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsSpeaker, let speaker = paragraph.speaker {
                Text(speaker.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(speaker == .me ? Color.accentColor : Color.purple)
                    .padding(.top, 14)
                    .padding(.leading, 64)
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Button(action: onPlay) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                            .opacity(isHovered ? 1 : 0)
                        Text(TranscriptFormatter.timestamp(paragraph.start))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .frame(width: 50, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("Play from here")

                Text(paragraph.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
        }
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isMatch { return Color.yellow.opacity(0.25) }
        if isCurrent { return Color.accentColor.opacity(0.12) }
        return .clear
    }
}
