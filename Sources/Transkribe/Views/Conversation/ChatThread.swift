import SwiftUI
import TranskribeCore

/// The transcript as a scrolling message thread.
struct ChatThread: View {
    let transcript: Transcript
    let isLive: Bool
    @Environment(AppModel.self) private var model
    @State private var flashID: Paragraph.ID?

    var body: some View {
        let paragraphs = ParagraphBuilder.paragraphs(from: transcript.segments)
        let me = transcript.resolvedMeSpeaker
        let items = ChatLayout.items(for: paragraphs, me: me)
        let starts = items.compactMap { item -> (start: TimeInterval, id: Paragraph.ID)? in
            if case .bubble(let bubble) = item { (bubble.paragraph.start, bubble.id) } else { nil }
        }
        let names = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0, transcript.name(of: $0)) })
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ConversationHeader(transcript: transcript, isLive: isLive)
                        .padding(.bottom, 18)
                    if transcript.hasSpeakers, me == nil, transcript.status == .done {
                        WhoIsMePrompt(transcript: transcript)
                            .padding(.bottom, 18)
                    }
                    ThreadStatus(transcript: transcript, isLive: isLive)
                    BubbleList(transcriptID: transcript.id, items: items, starts: starts, names: names,
                               labelsSpeakers: transcript.hasSpeakers, query: model.query, flashID: flashID, scroll: proxy)
                    if isLive {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .id("live-end")
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 26)
                .padding(.bottom, 130)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: transcript.segments.count) { _, _ in
                guard isLive else { return }
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo("live-end", anchor: .bottom) }
            }
            .task(id: model.focus?.token) {
                // Jump to a moment chosen in search, then highlight it for a moment.
                guard let focus = model.focus, focus.id == transcript.id else { return }
                guard let target = starts.last(where: { $0.start <= focus.time + 0.05 })?.id ?? starts.first?.id else { return }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.35)) }
                withAnimation(.easeIn(duration: 0.2)) { flashID = target }
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.8)) { flashID = nil }
            }
        }
    }
}

/// The only part of the thread that follows the playhead (20 times a second).
private struct BubbleList: View {
    let transcriptID: Transcript.ID
    let items: [ChatLayout.Item]
    /// Bubble start times in order, for finding the one being played without walking `items`.
    let starts: [(start: TimeInterval, id: Paragraph.ID)]
    let names: [Int: String]
    let labelsSpeakers: Bool
    let query: String
    let flashID: Paragraph.ID?
    let scroll: ScrollViewProxy
    @Environment(PlayerController.self) private var player

    var body: some View {
        let current = currentBubble
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                switch item {
                case .separator(let time):
                    Text(TranscriptFormatter.timestamp(time))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 14)
                case .bubble(let bubble):
                    BubbleView(
                        bubble: bubble,
                        name: bubble.paragraph.speaker.flatMap { names[$0] },
                        showsAvatar: labelsSpeakers,
                        playhead: bubble.id == current ? player.currentTime : nil,
                        query: query,
                        transcriptID: transcriptID,
                        speakers: names,
                        isFlashing: bubble.id == flashID
                    )
                    .equatable()
                    .id(bubble.id)
                }
            }
        }
        .onChange(of: current) { _, id in
            guard player.isPlaying, let id else { return }
            withAnimation(.easeInOut(duration: 0.45)) { scroll.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.4)) }
        }
    }

    private var currentBubble: Paragraph.ID? {
        guard player.isPlaying || player.currentTime > 0 else { return nil }
        let time = player.currentTime + 0.05
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? starts[low - 1].id : nil
    }
}

/// Animated "…" while a live recording is being transcribed.
struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([0.3, 1.0]) { view, opacity in
                        view.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.6).delay(Double(index) * 0.2)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.theirBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.leading, 36)
        .accessibilityLabel("Listening")
    }
}

/// Progress for work still running on this conversation.
private struct ThreadStatus: View {
    let transcript: Transcript
    let isLive: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch (transcript.status, model.activity[transcript.id]) {
            case (_, .live?):
                if transcript.segments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 34, weight: .light))
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .foregroundStyle(Theme.record)
                        Text("Listening")
                            .font(.title3.weight(.semibold))
                        Text("The conversation appears here as you talk, a few lines every half minute.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                }
            case (.pending, _):
                banner("Waiting to transcribe…", progress: nil)
            case (_, .transcribing(let progress)?):
                banner("Transcribing", progress: progress)
            case (_, .identifyingSpeakers?):
                banner("Identifying speakers", progress: nil)
            case (.failed(let message), _):
                HStack(spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Try Again") { model.retry(transcript.id) }
                }
                .padding(14)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 16)
            case (.done, nil) where transcript.segments.isEmpty:
                ContentUnavailableView("No speech found", systemImage: "waveform.slash",
                                       description: Text("This recording doesn't seem to contain any speech."))
            default:
                EmptyView()
            }
        }
        .animation(Theme.spring, value: model.activity[transcript.id])
    }

    private func banner(_ text: String, progress: Double?) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(text).font(.callout.weight(.medium))
                Spacer()
                if let progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout.monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: progress)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.bottom, 18)
    }
}
