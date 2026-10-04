import SwiftUI
import TranskribeCore

/// Floats over any screen while a recording runs, so you can keep reading old transcripts.
struct RecordingCapsule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if case .recording(let since) = model.recordingState {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.record)
                    .frame(width: 9, height: 9)
                    .phaseAnimator([1.0, 0.35]) { view, opacity in view.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.9) }
                ElapsedTime(since: since)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
                WaveformView(levels: Array(model.levels.suffix(18)))
                    .frame(width: 70, height: 20)
                Button {
                    model.selection = nil
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show recording")
                Button(action: model.stopRecording) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.record, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Stop recording (⌘R)")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassBackground(in: Capsule())
        }
    }
}

struct Toast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassBackground(in: Capsule())
    }
}
