import AppKit
import SwiftUI
import TranskribeCore

/// Home's palette: flat near-black ink in dark mode, warm paper in light mode.
enum Stage {
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.039, green: 0.039, blue: 0.051, alpha: 1)
            : NSColor(red: 0.975, green: 0.972, blue: 0.965, alpha: 1)
    })
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.055)
            : NSColor(white: 1, alpha: 1)
    })
    /// A card under the pointer: one step lighter in dark mode, a touch warmer in light mode.
    static let cardRaised = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.085)
            : NSColor(red: 0.995, green: 0.993, blue: 0.99, alpha: 1)
    })
    static let hairline = Color.primary.opacity(0.09)
}

/// Home's backdrop: one flat surface, nothing behind the controls competing with them.
struct StageBackdrop: View {
    var body: some View {
        Stage.canvas.ignoresSafeArea()
    }
}

/// The record button: a red disc in a ring, like a camera shutter. Crisp edges, no glow;
/// while recording a thin ring around it moves with your voice.
struct ShutterButton: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false
    static let diameter: CGFloat = 104
    var size: CGFloat = ShutterButton.diameter

    var body: some View {
        let recording = isRecording
        let level = CGFloat(min(1, pow(Double(model.levels.last ?? 0) * 6, 0.7)))
        Button(action: model.toggleRecording) {
            ZStack {
                Heartbeat(size: size, isRecording: recording, level: level, isHovered: isHovered)
                Circle()
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.42 : 0.24), lineWidth: 3)
                RoundedRectangle(cornerRadius: recording ? size * 0.07 : size * 0.4, style: .continuous)
                    .fill(Theme.record)
                    .frame(width: recording ? size * 0.34 : size * 0.8, height: recording ? size * 0.34 : size * 0.8)
                    .scaleEffect(isHovered && !recording ? 0.96 : 1)
                if model.recordingState == .starting {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(SquishStyle())
        .onHover { hovering in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isHovered = hovering } }
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: recording)
        .disabled(model.recordingState == .starting || model.recordingState == .stopping)
        .keyboardShortcut("r")
        .accessibilityLabel(recording ? "Stop recording" : "Start recording")
        .help(recording ? "Stop and transcribe (⌘R)" : "Start recording (⌘R)")
    }

    private var isRecording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }
}

/// One clean ring that ripples out when you point at the record button; while recording
/// it sits just outside the button and swells with your voice. Nothing animates on its own.
private struct Heartbeat: View {
    let size: CGFloat
    let isRecording: Bool
    let level: CGFloat
    let isHovered: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.record.opacity(isRecording ? 0.35 + Double(level) * 0.45 : 0), lineWidth: 1.5)
                .scaleEffect(isRecording ? 1.1 + level * 0.18 : 1)
                .animation(.easeOut(duration: 0.12), value: level)
            Circle()
                .stroke(Theme.record.opacity(pulse ? 0 : 0.5), lineWidth: 1)
                .scaleEffect(pulse ? 1.35 : 1)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onChange(of: isHovered) { _, hovering in
            guard hovering, !isRecording else { return }
            pulse = false
            withAnimation(.easeOut(duration: 0.9)) { pulse = true }
        }
        .onAppear { pulse = true }
    }
}

/// A quiet round action beside the record button, camera-app style.
struct SideButton: View {
    let symbol: String
    let title: String
    var keys: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0.035)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(isHovered ? 0.2 : 0.1), lineWidth: 1))
                    .frame(height: ShutterButton.diameter)
                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    if let keys { Keycap(text: keys) } else { Keycap(text: "⌘O").hidden() }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
    }
}

struct SquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// What to listen to, as three small pills under the record button.
struct SourcePills: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RecordingSource.allCases) { source in
                let selected = model.recordingSource == source
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { model.recordingSource = source }
                } label: {
                    Label(source.shortLabel, systemImage: source.symbol)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule().fill(Color.primary.opacity(0.1))
                                    .matchedGeometryEffect(id: "pill", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().strokeBorder(Stage.hairline, lineWidth: 1))
        .disabled(model.isRecording)
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}
