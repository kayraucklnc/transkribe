import SwiftUI
import TranskribeCore

/// The top of Home, built like a recorder: a large time readout, what it will listen to,
/// and three round buttons with Record in the middle.
struct Hero: View {
    @Environment(AppModel.self) private var model
    @Environment(DictationController.self) private var dictation
    @State private var appeared = false

    var body: some View {
        let recording = isRecording
        VStack(spacing: 0) {
            Readout()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            HStack(alignment: .top, spacing: 48) {
                SideButton(symbol: "arrow.down.doc", title: "Import") {
                    FileImport.presentOpenPanel(model: model)
                }
                .help("Transcribe an audio or video file (⌘O), or drop one anywhere")
                .disabled(recording)
                .opacity(recording ? 0.3 : 1)
                VStack(spacing: 10) {
                    ShutterButton()
                    Text(recording ? "Stop" : "Record")
                        .font(.system(size: 12, weight: .semibold))
                        .contentTransition(.opacity)
                }
                SideButton(symbol: "mic", title: "Dictate", keys: dictation.shortcut?.display) {
                    dictation.start()
                }
                .help("Speak, then press Return to type it into any app")
                .disabled(recording)
                .opacity(recording ? 0.3 : 1)
            }
            .padding(.top, 22)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)

            SourcePills()
                .padding(.top, 14)
                .opacity(appeared ? (recording ? 0.4 : 1) : 0)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: recording)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.05)) { appeared = true }
        }
    }

    private var isRecording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }
}

/// A big, thin time readout like a hardware recorder's. Dim at rest; while recording it
/// lights up and counts, with a red dot that beats once a second and a live level meter.
private struct Readout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                if case .recording(let since) = model.recordingState {
                    BeatingDot(since: since)
                        .transition(.scale.combined(with: .opacity))
                    ElapsedTime(since: since)
                } else {
                    Text(TranscriptFormatter.timestamp(0))
                        .foregroundStyle(Color.primary.opacity(0.22))
                }
            }
            .font(.system(size: 68, weight: .thin).monospacedDigit())
            .tracking(-1.5)
            .frame(height: 74)

            ZStack {
                if model.isRecording {
                    WaveformView(levels: Array(model.levels.suffix(48)))
                        .frame(width: 220, height: 22)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 7) {
                        Text("Ready")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Keycap(text: "⌘R")
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 22)
        }
        .animation(.easeOut(duration: 0.25), value: model.isRecording)
    }
}

/// A small red dot that fades in time with the seconds, so a recording visibly has a pulse.
private struct BeatingDot: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 0.5)) { context in
            let tick = Int(context.date.timeIntervalSince(since) * 2) % 2 == 0
            Circle()
                .fill(Theme.record)
                .frame(width: 12, height: 12)
                .opacity(tick ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.45), value: tick)
        }
        .accessibilityHidden(true)
    }
}

/// The question box: a quiet field with its shortcut, in the same material as the cards below.
struct AskBar: View {
    @Binding var isPresented: Bool
    @State private var isHovered = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Ask about your conversations")
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                Spacer()
                Keycap(text: "⌘K")
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Stage.card))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.2 : 0.09), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
        .keyboardShortcut("k")
        .help("Ask questions across every conversation, like “What did Hakan say about the price?”")
    }
}
