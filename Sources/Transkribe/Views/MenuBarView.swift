import SwiftUI
import TranskribeCore

/// Record without opening the window, e.g. while a meeting app is full screen.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(DictationController.self) private var dictation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            // Both layouts stay in place and only the active one shows, so the menu keeps one
            // size. A MenuBarExtra window resizes to fit its content, and resizing it while the
            // level meter redraws crashed AppKit ("Update Constraints in Window" loop).
            ZStack {
                recordingControls
                    .visible(isRecording)
                idleControls
                    .visible(!isRecording)
            }
            Button { dictation.start() } label: {
                HStack {
                    Label("Dictate", systemImage: "mic")
                    Spacer()
                    if let shortcut = dictation.shortcut {
                        Text(shortcut.display).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRecording)
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

    private var recordingSince: Date? {
        if case .recording(let since) = model.recordingState { return since }
        return nil
    }

    private var isRecording: Bool { recordingSince != nil }

    private var recordingControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(Theme.record).frame(width: 8, height: 8)
                Group {
                    if let since = recordingSince {
                        ElapsedTime(since: since)
                    } else {
                        // Holds the timer's place while hidden, without a ticking timeline.
                        Text(TranscriptFormatter.timestamp(0))
                    }
                }
                .font(.system(.title3, design: .rounded).weight(.medium))
                .monospacedDigit()
                Spacer()
                WaveformView(levels: isRecording ? Array(model.levels.suffix(20)) : [])
                    .frame(width: 80, height: 22)
            }
            Button(action: model.stopRecording) {
                Label("Stop & Transcribe", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Theme.record)
        }
    }

    private var idleControls: some View {
        VStack(spacing: 14) {
            Picker("Source", selection: Binding(get: { model.recordingSource }, set: { model.recordingSource = $0 })) {
                ForEach(RecordingSource.allCases) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button { model.startRecording() } label: {
                Label("Start Recording", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Theme.record)
            .disabled(model.recordingState != .idle)
        }
    }
}

private extension View {
    /// Shows or hides the view but always keeps its space, so the layout never changes size.
    func visible(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .disabled(!isVisible)
            .accessibilityHidden(!isVisible)
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    // Keep this static: a menu bar label that changes every second (like a running timer)
    // makes SwiftUI rebuild the status item in a loop that pins the CPU and leaks memory.
    // The timer lives inside the menu instead.
    var body: some View {
        Image(systemName: model.isRecording ? "record.circle.fill" : "waveform")
            .onAppear { MainWindow.opener = { openWindow(id: "main") } }
    }
}
