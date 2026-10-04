import SwiftUI
import TranskribeCore

/// The home screen: one big record button, a source picker, and a hint to drop files.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 28) {
            Spacer()
            RecordButton()
            VStack(spacing: 6) {
                Text(headline)
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Picker("Record from", selection: $model.recordingSource) {
                ForEach(RecordingSource.allCases) { source in
                    Label(source.label, systemImage: source.symbol).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.isRecording)
            Spacer()
            HStack(spacing: 4) {
                Text("Or drop any audio or video file here.")
                    .foregroundStyle(.secondary)
                Button("Choose File…") { FileImport.presentOpenPanel(model: model) }
                    .buttonStyle(.link)
            }
            .font(.callout)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headline: String {
        switch model.recordingState {
        case .idle: "Record a conversation"
        case .starting: "Starting…"
        case .recording: "Recording"
        case .stopping: "Saving…"
        }
    }

    private var caption: String {
        switch model.recordingSource {
        case .microphone: "Records your microphone."
        case .system: "Records everything your Mac plays — calls, videos, meetings."
        case .both: "Records you and the other side of a call. Each speaker is labeled."
        }
    }
}

struct RecordButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: model.toggleRecording) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .scaleEffect(1 + CGFloat(min(model.level * 4, 0.35)))
                    .opacity(isRecording ? 1 : 0)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 4)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 40)
                    .fill(Color.red)
                    .frame(width: isRecording ? 34 : 80, height: isRecording ? 34 : 80)
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
            .animation(.spring(duration: 0.3), value: isRecording)
            .animation(.easeOut(duration: 0.12), value: model.level)
        }
        .buttonStyle(.plain)
        .disabled(model.recordingState == .starting || model.recordingState == .stopping)
        .overlay(alignment: .bottom) {
            if case .recording(let since) = model.recordingState {
                ElapsedTime(since: since)
                    .font(.title2.monospacedDigit())
                    .offset(y: 44)
            }
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .help(isRecording ? "Stop recording (⌘R)" : "Start recording (⌘R)")
    }

    private var isRecording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }
}

struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(TranscriptFormatter.timestamp(context.date.timeIntervalSince(since)))
        }
    }
}

/// Toolbar control that's always reachable, even while a transcript is open.
struct RecordToolbarControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if case .recording(let since) = model.recordingState {
            Button(action: model.stopRecording) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill").foregroundStyle(.red)
                    ElapsedTime(since: since).monospacedDigit()
                }
            }
            .help("Stop recording (⌘R)")
        } else {
            Menu {
                Picker("Record from", selection: $model.recordingSource) {
                    ForEach(RecordingSource.allCases) { source in
                        Label(source.label, systemImage: source.symbol).tag(source)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Record", systemImage: "record.circle")
            } primaryAction: {
                model.selection = nil
                model.startRecording()
            }
            .disabled(model.recordingState != .idle)
            .help("Record \(model.recordingSource.label.lowercased()) (⌘R)")
        }
    }
}
