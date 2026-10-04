import SwiftUI

/// Progress for long-running work (transcribing, finding speakers): rippling voice bars,
/// a live percentage, time left, and a gradient track with a moving sheen.
struct WorkingCard: View {
    let title: String
    let subtitle: String?
    /// nil = indeterminate.
    let progress: Double?

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                VoiceBars()
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
                if let progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))
                        .animation(.snappy, value: progress)
                }
            }
            ProgressTrack(progress: progress)
                .frame(height: 6)
        }
        .padding(18)
        .frame(maxWidth: 560)
        .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct VoiceBars: View {
    private let heights: [CGFloat] = [0.45, 0.8, 1, 0.7, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [.accentColor, .purple], startPoint: .bottom, endPoint: .top))
                    .frame(width: 4)
                    .phaseAnimator([0.35, 1.0]) { bar, scale in
                        bar.scaleEffect(y: scale * heights[index], anchor: .center)
                    } animation: { _ in
                        .easeInOut(duration: 0.55).delay(Double(index) * 0.09)
                    }
            }
        }
    }
}

private struct ProgressTrack: View {
    let progress: Double?
    @State private var sweep = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let filled = progress.map { max(8, width * min(1, $0)) } ?? width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [.accentColor, .purple, .pink], startPoint: .leading, endPoint: .trailing))
                    .opacity(progress == nil ? 0.35 : 1)
                    .frame(width: filled)
                    .overlay {
                        // A soft highlight that keeps moving, so it's alive even between updates.
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 80)
                            .offset(x: sweep ? filled : -80)
                            .frame(width: filled, alignment: .leading)
                            .clipShape(Capsule())
                    }
                    .animation(.spring(response: 0.6, dampingFraction: 0.9), value: filled)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}
