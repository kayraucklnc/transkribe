import SwiftUI

/// Progress for long-running work (transcribing, finding speakers): voice bars that move while
/// it works, a live percentage, time left, and the system's own progress bar.
struct WorkingCard: View {
    let title: String
    let subtitle: String?
    /// nil = indeterminate.
    let progress: Double?
    /// Waiting for the Mac: the bars rest and the progress bar dims, keeping how far it got.
    var isPaused = false
    /// An optional button, e.g. "Continue Anyway" while paused.
    var action: (title: String, run: () -> Void)?
    /// Set when the button was pressed, until the card changes (the work resumed).
    @State private var actionTaken = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                VoiceBars(isMoving: !isPaused || actionTaken)
                    .frame(width: 34, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }
                Spacer()
                if let action {
                    Button {
                        actionTaken = true
                        action.run()
                    } label: {
                        if actionTaken {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Continuing…")
                            }
                        } else {
                            Text(action.title)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.record)
                    .controlSize(.regular)
                    .disabled(actionTaken)
                }
                if let progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isPaused ? .secondary : .primary)
                        .contentTransition(.numericText(value: progress))
                        .animation(.snappy, value: progress)
                }
            }
            Group {
                if let progress {
                    ProgressView(value: min(1, max(0, progress)))
                        .animation(.smooth(duration: 0.6), value: progress)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(isPaused ? Color.secondary : Color.accentColor)
        }
        .padding(18)
        .frame(maxWidth: 560)
        .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct VoiceBars: View {
    let isMoving: Bool
    private let heights: [CGFloat] = [0.45, 0.8, 1, 0.7, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                if isMoving {
                    bar(index)
                        .phaseAnimator([0.35, 1.0]) { bar, scale in
                            bar.scaleEffect(y: scale * heights[index], anchor: .center)
                        } animation: { _ in
                            .easeInOut(duration: 0.55).delay(Double(index) * 0.09)
                        }
                } else {
                    bar(index).scaleEffect(y: heights[index] * 0.6, anchor: .center)
                }
            }
        }
        .foregroundStyle(isMoving ? Color.accentColor : Color.secondary)
        .animation(.easeOut(duration: 0.3), value: isMoving)
    }

    private func bar(_ index: Int) -> some View {
        Capsule().frame(width: 4)
    }
}
