import SwiftUI
import TranskribeCore
import UniformTypeIdentifiers

/// A conversation as a messaging thread, with playback and (optionally) the insights panel.
struct ConversationView: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model
    @Environment(PlayerController.self) private var player
    @AppStorage("showsInsights") private var showsInsights = true
    @State private var showsFind = false
    @State private var isJoining = false

    private var isLive: Bool { model.liveRecordingID == transcript.id }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ChatThread(transcript: transcript, isLive: isLive)
                    .overlay(alignment: .top) {
                        if showsFind || !model.query.isEmpty {
                            FindBar(transcript: transcript) {
                                showsFind = false
                                model.query = ""
                            }
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(Theme.spring, value: showsFind || !model.query.isEmpty)
                    .background {
                        Button("") { showsFind = true }
                            .keyboardShortcut("f")
                            .hidden()
                    }
                    .overlay(alignment: .bottom) {
                        Group {
                            if isLive {
                                LiveRecordingBar()
                            } else if !transcript.tracks.isEmpty {
                                PlayerCapsule(transcript: transcript)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 18)
                    }
            }
            .frame(minWidth: 380, maxWidth: .infinity)
            .layoutPriority(1)
            .background(Theme.canvas)
            if showsInsights, !isLive {
                InsightsPanel(transcript: transcript)
                    .frame(width: 380)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: showsInsights)
        .navigationTitle("")
        .toolbar { toolbar }
        .task(id: transcript.id) {
            guard !isLive else { return }
            await player.load(transcript, store: model.store)

        }
        .onChange(of: isLive) { _, live in
            guard !live else { return }
            Task { await player.reload(transcript, store: model.store) }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            // Typing a space in a text field (title, questions) must not toggle playback.
            if NSApp.keyWindow?.firstResponder is NSText { return .ignored }
            player.togglePlayback()
            return .handled
        }
        .onExitCommand { withAnimation(Theme.spring) { model.selection = nil } }
        .onDisappear { player.stop() }
        .sheet(isPresented: $isJoining) {
            JoinConversationSheet(transcript: transcript) { isJoining = false }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(Theme.spring) { model.selection = nil }
            } label: {
                Label("Library", systemImage: "chevron.left")
            }
            .help("Back to all conversations (Esc)")
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        ToolbarItemGroup {
            Button {
                model.recordFollowUp(of: transcript)
            } label: {
                Label("Record Follow-up", systemImage: "record.circle")
            }
            .help("Record the next part of this conversation")
            .disabled(model.isRecording || isLive)

            ShareLink(item: DocumentExport.markdown(transcript, people: model.people),
                      subject: Text(transcript.title), preview: SharePreview(transcript.title)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share the conversation as a document")
            .disabled(transcript.segments.isEmpty)

            Button {
                model.copyText(of: transcript.id)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy transcript (⇧⌘C)")
            .disabled(transcript.segments.isEmpty)

            Menu {
                Section("Export") {
                    Button("PDF Document") { export(.pdf) }
                    Button("Markdown Document") { export(.markdown) }
                    Button("Plain Text") { export(.plainText) }
                    Button("Subtitles (SRT)") { export(.srt) }
                }
                Section("Conversation") {
                    Button("Add to Another Conversation…") { isJoining = true }
                    if transcript.threadID != nil {
                        Button("Remove from This Conversation") { model.removeFromConversation(transcript.id) }
                    }
                }
                Section {
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

            Button {
                showsInsights.toggle()
            } label: {
                Label("Insights", systemImage: "sparkles")
            }
            .help("Summary and questions")
            .disabled(isLive)
        }
    }

    private enum ExportFormat: String {
        case plainText = "txt", markdown = "md", srt, pdf
    }

    private func export(_ format: ExportFormat) {
        let text = switch format {
        case .plainText: TranscriptFormatter.plainText(transcript)
        case .markdown: DocumentExport.markdown(transcript, people: model.people)
        case .srt: TranscriptFormatter.srt(transcript)
        case .pdf: ""
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(transcript.title).\(format.rawValue)"
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if format == .pdf {
                try PDFExport.write(html: DocumentExport.html(transcript, people: model.people), to: url)
                model.showToast("Exported")
                return
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            model.showToast("Exported")
        } catch {
            model.show(message: "Couldn't save the file. \(error.localizedDescription)")
        }
    }
}

/// Timer, live waveform and stop button while the conversation is being recorded.
struct LiveRecordingBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Theme.record)
                .frame(width: 10, height: 10)
                .phaseAnimator([1.0, 0.3]) { view, opacity in view.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.9) }
            if case .recording(let since) = model.recordingState {
                ElapsedTime(since: since)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            } else {
                Text("Finishing…").font(.callout).foregroundStyle(.secondary)
            }
            WaveformView(levels: model.levels)
                .frame(height: 30)
            Button(action: model.stopRecording) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.record, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.recordingState != .recording(since: sinceDate))
            .keyboardShortcut("r")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 640)
        .glassBackground(in: Capsule())
    }

    private var sinceDate: Date {
        if case .recording(let since) = model.recordingState { return since }
        return .distantPast
    }
}
