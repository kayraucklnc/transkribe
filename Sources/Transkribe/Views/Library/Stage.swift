import AppKit
import SwiftUI
import TranskribeCore

/// Home's palette: a deep, near-black stage in dark mode, warm paper in light mode.
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
    static let hairline = Color.primary.opacity(0.09)
}

/// Fine lines that drift like a resting sound wave and swell with your voice while recording.
struct SoundField: View {
    var level: Double
    var isRecording: Bool
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: activeState == .inactive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let mid = size.height / 2
                let lines = 6
                for line in 0..<lines {
                    let index = Double(line)
                    let swell = isRecording ? 16 + level * 120 : 14 + 6 * sin(time * 0.6 + index)
                    let amplitude = swell * (1 - index * 0.11)
                    let frequency = 2.2 + index * 0.35
                    let speed = (isRecording ? 2.4 : 0.55) + index * 0.12
                    var path = Path()
                    let steps = 90
                    for step in 0...steps {
                        let x = Double(step) / Double(steps)
                        // Pinned at the edges, free in the middle (behind the record button).
                        let envelope = pow(sin(.pi * x), 2.4)
                        let y = mid + amplitude * envelope * sin(x * .pi * frequency + time * speed + index * 1.3)
                        let point = CGPoint(x: x * size.width, y: y)
                        step == 0 ? path.move(to: point) : path.addLine(to: point)
                    }
                    let tint: Color = isRecording && line == 0 ? Theme.record : .primary
                    canvas.stroke(path, with: .color(tint.opacity(line == 0 ? 0.55 : 0.16 - index * 0.015)),
                                  lineWidth: line == 0 ? 1.6 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The record button: a red disc in a ring, with a slow heartbeat so the eye finds it first.
struct ShutterButton: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false
    static let diameter: CGFloat = 116
    var size: CGFloat = ShutterButton.diameter

    var body: some View {
        let recording = isRecording
        let level = CGFloat(min(1, pow(Double(model.levels.last ?? 0) * 6, 0.7)))
        Button(action: model.toggleRecording) {
            ZStack {
                Heartbeat(size: size, isRecording: recording, level: level)
                Circle()
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.55 : 0.32), lineWidth: 3.5)
                RoundedRectangle(cornerRadius: recording ? size * 0.09 : size * 0.4, style: .continuous)
                    .fill(Theme.record)
                    .frame(width: recording ? size * 0.36 : size * 0.8, height: recording ? size * 0.36 : size * 0.8)
                    .scaleEffect(isHovered && !recording ? 0.95 : 1)
                    .shadow(color: Theme.record.opacity(0.45), radius: recording ? 8 + level * 20 : 14, y: 2)
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

/// Two quick rings every couple of seconds, like a pulse; while recording, rings follow your voice.
private struct Heartbeat: View {
    let size: CGFloat
    let isRecording: Bool
    let level: CGFloat
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40, paused: activeState == .inactive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { beat in
                    let phase = isRecording
                        ? (time * 0.9 + Double(beat) * 0.5).truncatingRemainder(dividingBy: 1)
                        : max(0, ((time / 2.4).truncatingRemainder(dividingBy: 1) - Double(beat) * 0.12) / 0.55)
                    let progress = min(1, phase)
                    Circle()
                        .stroke(Theme.record.opacity((1 - progress) * (isRecording ? 0.35 + Double(level) * 0.5 : 0.45)),
                                lineWidth: 1.5)
                        .scaleEffect(1 + progress * (isRecording ? 0.35 + level * 0.5 : 0.42))
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
    }
}

/// A round secondary action beside the record button, camera-app style.
struct SideButton: View {
    let symbol: String
    let title: String
    var keys: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.14 : 0.075)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(isHovered ? 0.25 : 0.1), lineWidth: 1))
                    .scaleEffect(isHovered ? 1.06 : 1)
                    .frame(height: ShutterButton.diameter)
                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let keys { Keycap(text: keys) } else { Keycap(text: "⌘O").hidden() }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .onHover { hovering in withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { isHovered = hovering } }
    }
}

struct SquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
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
