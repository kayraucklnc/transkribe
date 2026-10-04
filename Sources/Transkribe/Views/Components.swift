import SwiftUI
import TranskribeCore

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

/// Wraps children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let previous = rows[rows.count - 1]
                rows.append(Row(y: previous.y + previous.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
