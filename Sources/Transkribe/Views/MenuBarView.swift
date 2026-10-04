import SwiftUI
import TranskribeCore

/// Record without opening the window, e.g. while a meeting app is full screen.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            if case .recording(let since) = model.recordingState {
                HStack(spacing: 10) {
                    Circle().fill(Theme.record).frame(width: 8, height: 8)
                    ElapsedTime(since: since)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()
                    Spacer()
                    WaveformView(levels: Array(model.levels.suffix(20)))
                        .frame(width: 80, height: 22)
                }
                Button(action: model.stopRecording) {
                    Label("Stop & Transcribe", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Theme.record)
            } else {
                Picker("Source", selection: Binding(get: { model.recordingSource }, set: { model.recordingSource = $0 })) {
                    ForEach(RecordingSource.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button(action: model.startRecording) {
                    Label("Start Recording", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Theme.record)
                .disabled(model.recordingState != .idle)
            }
            Divider()
            HStack {
                Button("Open Transkribe") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 280)
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if case .recording(let since) = model.recordingState {
            HStack(spacing: 4) {
                Image(systemName: "record.circle.fill")
                ElapsedTime(since: since).monospacedDigit()
            }
        } else {
            Image(systemName: "waveform")
        }
    }
}
