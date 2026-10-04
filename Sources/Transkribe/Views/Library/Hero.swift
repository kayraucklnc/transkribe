import SwiftUI
import TranskribeCore

/// The top of Home: a big promise, the sound field, and three round buttons with Record in the middle.
struct Hero: View {
    @Environment(AppModel.self) private var model
    @Environment(DictationController.self) private var dictation
    @State private var appeared = false

    var body: some View {
        let recording = isRecording
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(recording ? "Listening." : "Every word, kept.")
                    .font(.system(size: 50, weight: .bold))
                    .tracking(-1.2)
                    .contentTransition(.opacity)
                Group {
                    if case .recording(let since) = model.recordingState {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.record).frame(width: 7, height: 7)
                            ElapsedTime(since: since).monospacedDigit()
                            Text("· \(model.recordingSource.label)")
                        }
                    } else {
                        Text("Record a conversation, drop in a file, or dictate into any app.")
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)

            ZStack {
                SoundField(level: Double(model.levels.last ?? 0) * 4, isRecording: recording)
                    .frame(height: 220)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                                 .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                HStack(alignment: .top, spacing: 56) {
                    SideButton(symbol: "arrow.down.doc", title: "Import") {
                        FileImport.presentOpenPanel(model: model)
                    }
                    .help("Transcribe an audio or video file (⌘O), or drop one anywhere")
                    .disabled(recording)
                    .opacity(recording ? 0.35 : 1)
                    VStack(spacing: 12) {
                        ShutterButton()
                        Text(recording ? "Stop" : "Record")
                            .font(.system(size: 13, weight: .semibold))
                            .contentTransition(.opacity)
                    }
                    SideButton(symbol: "mic", title: "Dictate", keys: dictation.shortcut?.display) {
                        dictation.start()
                    }
                    .help("Speak, then press Return to type it into any app")
                    .disabled(recording)
                    .opacity(recording ? 0.35 : 1)
                }
            }
            .padding(.top, 34)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            SourcePills()
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: recording)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.82).delay(0.05)) { appeared = true }
        }
    }

    private var isRecording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }
}

/// The question box, with a thin light that travels around its edge.
struct AskBar: View {
    @Binding var isPresented: Bool
    @State private var isHovered = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: isHovered)
                Text("Ask anything about your conversations")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Spacer()
                Keycap(text: "⌘K")
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(Capsule().fill(Stage.card))
            .overlay(Capsule().strokeBorder(Stage.hairline, lineWidth: 1))
            .overlay {
                EdgeLight()
                    .opacity(isHovered ? 1 : 0.65)
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovered ? 1.012 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isHovered = hovering } }
        .keyboardShortcut("k")
        .help("Ask questions across every conversation, like “What did Hakan say about the price?”")
    }
}

/// A short streak of light circling a capsule's border. The gradient only rotates, so Core Animation
/// runs it at the display's refresh rate without redrawing anything on the main thread.
private struct EdgeLight: View {
    @State private var spinning = false

    var body: some View {
        GeometryReader { proxy in
            let side = hypot(proxy.size.width, proxy.size.height)
            AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .primary.opacity(0.7), location: 0.04),
                                    .init(color: .clear, location: 0.1), .init(color: .clear, location: 1)],
                            center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .mask(Capsule().strokeBorder(lineWidth: 1.2))
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { spinning = true }
        }
    }
}
