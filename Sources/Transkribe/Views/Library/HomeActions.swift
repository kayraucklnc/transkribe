import SwiftUI
import TranskribeCore

/// The three ways in: record a conversation, transcribe a file, or dictate into any app.
struct HomeActions: View {
    @Environment(AppModel.self) private var model
    @Environment(DictationController.self) private var dictation

    var body: some View {
        HStack(spacing: 14) {
            RecordTile()
            ActionTile(symbol: "arrow.down.doc.fill", tint: .blue, title: "Transcribe a File",
                       subtitle: "Any audio or video") {
                FileImport.presentOpenPanel(model: model)
            }
            .help("Choose an audio or video file (⌘O)")
            ActionTile(symbol: "mic.fill", tint: Color(nsColor: .systemGray), title: "Dictate",
                       subtitle: nil, keys: dictation.shortcut?.display) {
                dictation.start()
            }
            .help("Speak, then press Return to type it into any app")
            .disabled(model.isRecording)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A System Settings-style tile: a small colored icon square, a title and one line of detail.
private struct ActionTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?
    var keys: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TileLayout {
                IconSquare(symbol: symbol, tint: tint)
            } title: {
                Text(title)
            } detail: {
                if let keys {
                    Keycap(text: keys)
                } else if let subtitle {
                    Text(subtitle)
                }
            }
        }
        .buttonStyle(TileStyle())
    }
}

/// Record, or, while recording, the elapsed time with a live meter and a stop button.
private struct RecordTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: model.toggleRecording) {
            TileLayout {
                IconSquare(symbol: isRecording ? "stop.fill" : "record.circle", tint: Theme.record)
                    .contentTransition(.symbolEffect(.replace))
            } title: {
                if case .recording(let since) = model.recordingState {
                    HStack(spacing: 8) {
                        ElapsedTime(since: since).monospacedDigit()
                        WaveformView(levels: Array(model.levels.suffix(18)))
                            .frame(width: 54, height: 14)
                    }
                } else {
                    Text("Record")
                }
            } detail: {
                if isRecording {
                    Text("Click to stop and transcribe")
                } else {
                    // A menu inside the tile picks what to listen to without starting.
                    Menu {
                        Picker("Listen to", selection: Binding(get: { model.recordingSource }, set: { model.recordingSource = $0 })) {
                            ForEach(RecordingSource.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(model.recordingSource.label)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.visible)
                    .fixedSize()
                }
            }
        }
        .buttonStyle(TileStyle(isActive: isRecording))
        .disabled(model.recordingState == .starting || model.recordingState == .stopping)
        .help(isRecording ? "Stop recording (⌘R)" : "Start recording (⌘R)")
        .animation(Theme.spring, value: isRecording)
    }

    private var isRecording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }
}

private struct TileLayout<Icon: View, Title: View, Detail: View>: View {
    @ViewBuilder let icon: Icon
    @ViewBuilder let title: Title
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                detail
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 17, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct IconSquare: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// Flat surface with a hairline border; hover and press only change the fill.
struct TileStyle: ButtonStyle {
    var isActive = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill(pressed: configuration.isPressed)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? Theme.record.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: isActive ? 1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return Color.primary.opacity(0.1) }
        if isActive { return Theme.record.opacity(0.08) }
        return isHovered ? Color.primary.opacity(0.05) : Surface.raised
    }
}

/// Plain, system-matched surfaces instead of glows and gradients.
enum Surface {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let raised = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
}
