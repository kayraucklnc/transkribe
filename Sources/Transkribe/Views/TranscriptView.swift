import SwiftUI
import TranskribeCore
import UniformTypeIdentifiers

struct TranscriptView: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model
    @Environment(PlayerController.self) private var player
    @State private var title = ""
    @State private var followsPlayback = true

    var body: some View {
        // Computed once per transcript change; playback ticks only update `ParagraphList`.
        let paragraphs = ParagraphBuilder.paragraphs(from: transcript.segments)
        let hasSpeakers = transcript.hasSpeakers
        let names = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0, transcript.name(of: $0)) })
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if hasSpeakers {
                        SpeakerLegend(transcript: transcript)
                            .padding(.bottom, 26)
                    } else if transcript.status == .done, !transcript.segments.isEmpty {
                        SpeakerCountMenu(transcript: transcript)
                            .padding(.bottom, 22)
                    }
                    StatusView(transcript: transcript)
                    ParagraphList(transcriptID: transcript.id, paragraphs: paragraphs, names: names, labelsSpeakers: hasSpeakers,
                                  query: model.query, followsPlayback: followsPlayback, scroll: proxy)
                }
                .padding(.horizontal, 48)
                .padding(.top, 30)
                .padding(.bottom, 130)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
        }
        .overlay(alignment: .bottom) {
            if !transcript.tracks.isEmpty {
                PlayerCapsule(transcript: transcript)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
            }
        }
        .navigationTitle("")
        .toolbar { toolbar }
        .task(id: transcript.id) {
            title = transcript.title
            await player.load(transcript, store: model.store)
        }
        .onChange(of: transcript.title) { _, newValue in title = newValue }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            player.togglePlayback()
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Untitled", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .bold))
                .onSubmit { model.rename(transcript.id, to: title) }
            HStack(spacing: 14) {
                MetaLabel(symbol: "calendar", text: transcript.createdAt.formatted(date: .abbreviated, time: .shortened))
                MetaLabel(symbol: "clock", text: TranscriptFormatter.timestamp(transcript.duration))
                if let code = transcript.language, let name = Locale.current.localizedString(forLanguageCode: code) {
                    MetaLabel(symbol: "globe", text: name.capitalized(with: Locale.current))
                }
                if transcript.hasSpeakers {
                    MetaLabel(symbol: "person.2", text: "\(transcript.speakers.count) speakers")
                }
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        ToolbarItemGroup {
            Button {
                model.copyText(of: transcript.id)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy transcript (⇧⌘C)")
            .disabled(transcript.segments.isEmpty)

            Menu {
                Section("Export") {
                    Button("Text") { export(.plainText) }
                    Button("Markdown") { export(.markdown) }
                    Button("Subtitles (SRT)") { export(.srt) }
                }
                Section {
                    Menu("Number of Speakers") {
                        Button("Detect Automatically") { model.setSpeakerCount(nil, for: transcript.id) }
                        Divider()
                        ForEach(1...6, id: \.self) { count in
                            Button("\(count)") { model.setSpeakerCount(count, for: transcript.id) }
                        }
                    }
                    .disabled(transcript.status != .done)
                    Button("Transcribe Again") { model.transcribeAgain(transcript.id) }
                        .disabled(model.activity[transcript.id] != nil)
                    Button("Show in Finder") { model.revealInFinder(transcript.id) }
                }
                Section {
                    Button("Delete", role: .destructive) { model.delete(transcript.id) }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .help("Export, speakers and more")
        }
    }

    private enum ExportFormat: String {
        case plainText = "txt", markdown = "md", srt
    }

    private func export(_ format: ExportFormat) {
        let text = switch format {
        case .plainText: TranscriptFormatter.plainText(transcript)
        case .markdown: TranscriptFormatter.markdown(transcript)
        case .srt: TranscriptFormatter.srt(transcript)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(transcript.title).\(format.rawValue)"
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            model.showToast("Exported")
        } catch {
            model.show(message: "Couldn't save the file. \(error.localizedDescription)")
        }
    }
}

private struct MetaLabel: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

/// Progress for work still running on this transcript.
private struct StatusView: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch (transcript.status, model.activity[transcript.id]) {
            case (.pending, _):
                banner("Waiting to transcribe…", symbol: "clock", progress: nil)
            case (_, .transcribing(let progress)?):
                banner("Transcribing", symbol: "waveform", progress: progress)
            case (_, .identifyingSpeakers?):
                banner("Identifying speakers", symbol: "person.2.wave.2", progress: nil)
            case (.failed(let message), _):
                HStack(spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Try Again") { model.retry(transcript.id) }
                }
                .padding(14)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            case (.done, nil) where transcript.segments.isEmpty:
                ContentUnavailableView("No speech found", systemImage: "waveform.slash",
                                       description: Text("This recording doesn't seem to contain any speech."))
            default:
                EmptyView()
            }
        }
        .padding(.bottom, 22)
        .animation(Theme.spring, value: model.activity[transcript.id])
    }

    private func banner(_ text: String, symbol: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text(text)
                Spacer()
                if let progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: progress).progressViewStyle(.linear).tint(.accentColor)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
    }
}

/// The only part of the transcript that follows the playhead.
private struct ParagraphList: View {
    let transcriptID: Transcript.ID
    let paragraphs: [Paragraph]
    let names: [Int: String]
    let labelsSpeakers: Bool
    let query: String
    let followsPlayback: Bool
    let scroll: ScrollViewProxy
    @Environment(PlayerController.self) private var player

    var body: some View {
        let current = currentParagraph
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(paragraphs.enumerated()), id: \.element.id) { index, paragraph in
                ParagraphView(
                    paragraph: paragraph,
                    speakerName: paragraph.speaker.flatMap { names[$0] },
                    showsSpeaker: labelsSpeakers
                        && paragraph.speaker != nil
                        && (index == 0 || paragraphs[index - 1].speaker != paragraph.speaker),
                    playhead: paragraph.id == current ? player.currentTime : nil,
                    query: query,
                    transcriptID: transcriptID,
                    speakers: names
                )
                .equatable()
                .id(paragraph.id)
            }
        }
        .onChange(of: current) { _, id in
            guard player.isPlaying, followsPlayback, let id else { return }
            withAnimation(.easeInOut(duration: 0.45)) { scroll.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.35)) }
        }
    }

    /// Binary search for the last paragraph starting at or before the playhead.
    private var currentParagraph: Paragraph.ID? {
        guard player.isPlaying || player.currentTime > 0 else { return nil }
        let time = player.currentTime + 0.05
        var low = 0, high = paragraphs.count
        while low < high {
            let mid = (low + high) / 2
            if paragraphs[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? paragraphs[low - 1].id : nil
    }
}
