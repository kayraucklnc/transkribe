import SwiftUI
import TranskribeCore

/// The first thing you see: one big button. Everything else is optional.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            RecordButton(size: 132)
                .padding(.bottom, 30)
            Group {
                if case .recording(let since) = model.recordingState {
                    recordingDetails(since: since)
                } else {
                    idleDetails
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            Spacer(minLength: 40)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.spring, value: model.recordingState)
    }

    private var idleDetails: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text(model.recordingState == .stopping ? "Saving…" : "Start recording")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .contentTransition(.opacity)
            }
            SourcePicker()
                .disabled(model.isRecording)
        }
    }

    private func recordingDetails(since: Date) -> some View {
        VStack(spacing: 18) {
            ElapsedTime(since: since)
                .font(.system(size: 46, weight: .light, design: .rounded))
                .monospacedDigit()
            WaveformView(levels: model.levels)
                .frame(width: 300, height: 54)
            Label(model.recordingSource.recordingDescription, systemImage: model.recordingSource.symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
            Text("Drop audio or video anywhere to transcribe it.")
            Button("Choose File…") { FileImport.presentOpenPanel(model: model) }
                .buttonStyle(.link)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.bottom, 26)
    }

    private var caption: String {
        switch model.recordingSource {
        case .microphone: "Your microphone. Great for in-person conversations and notes."
        case .system: "Everything your Mac plays: calls, meetings, videos."
        case .both: "You and the other side of a call, each labeled."
        }
    }
}

extension RecordingSource {
    var shortLabel: String {
        switch self {
        case .microphone: "Mic"
        case .system: "System"
        case .both: "Both"
        }
    }

    var recordingDescription: String {
        switch self {
        case .microphone: "Recording microphone"
        case .system: "Recording system audio"
        case .both: "Recording microphone and system audio"
        }
    }
}

struct RecordButton: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        let recording = isRecording
        let level = CGFloat(min(1, pow(Double(model.levels.last ?? 0) * 6, 0.7)))
        Button(action: model.toggleRecording) {
            ZStack {
                // Halo that breathes with the input level while recording.
                Circle()
                    .fill(Theme.record.opacity(0.18))
                    .scaleEffect(recording ? 1.08 + level * 0.28 : 0.9)
                    .opacity(recording ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: level)
                Circle()
                    .fill(.clear)
                    .glassBackground(in: Circle(), interactive: true)
                RoundedRectangle(cornerRadius: recording ? size * 0.09 : size * 0.3, style: .continuous)
                    .fill(Theme.record.gradient)
                    .frame(width: recording ? size * 0.3 : size * 0.6, height: recording ? size * 0.3 : size * 0.6)
                    .shadow(color: Theme.record.opacity(0.45), radius: isHovered ? 14 : 8, y: 3)
                if model.recordingState == .starting {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(isPressed ? 0.94 : (isHovered ? 1.03 : 1))
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle(isPressed: $isPressed))
        .onHover { hovering in withAnimation(Theme.spring) { isHovered = hovering } }
        .animation(Theme.spring, value: recording)
        .disabled(model.recordingState == .starting || model.recordingState == .stopping)
        .accessibilityLabel(recording ? "Stop recording" : "Start recording")
        .help(recording ? "Stop recording (⌘R)" : "Start recording (⌘R)")
    }

    private var isRecording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }
}

/// Reports the pressed state so the button can shrink with a spring.
struct PressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isPressed = pressed }
            }
    }
}

struct SourcePicker: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RecordingSource.allCases) { source in
                let selected = model.recordingSource == source
                Button {
                    withAnimation(Theme.spring) { model.recordingSource = source }
                } label: {
                    Label(source.label, systemImage: source.symbol)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.1))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassBackground(in: Capsule())
    }
}

/// Scrolling level bars, newest on the right.
struct WaveformView: View {
    let levels: [Float]
    var color: Color = Theme.record

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }
            let spacing: CGFloat = 3
            let width = max(1.5, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            for (index, level) in levels.enumerated() {
                let amplitude = min(1, pow(CGFloat(level) * 6, 0.7))
                let height = max(width, amplitude * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * (width + spacing),
                    y: (size.height - height) / 2,
                    width: width,
                    height: height
                )
                let fade = 0.35 + 0.65 * Double(index) / Double(count)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color.opacity(fade)))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(TranscriptFormatter.timestamp(context.date.timeIntervalSince(since)))
                .contentTransition(.numericText())
        }
    }
}
