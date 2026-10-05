import SwiftUI
import TranskribeCore

/// Floating glass player. The scrubber doubles as a map of who spoke when.
struct PlayerCapsule: View {
    let transcript: Transcript
    @Environment(PlayerController.self) private var player
    @State private var scrubTime: TimeInterval?

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                iconButton("gobackward.15", help: "Back 15 seconds") { player.skip(by: -15) }
                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.gradient, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
                iconButton("goforward.15", help: "Forward 15 seconds") { player.skip(by: 15) }
            }

            Text(TranscriptFormatter.timestamp(scrubTime ?? player.currentTime))
                .frame(minWidth: 40, alignment: .trailing)

            SpeakerTimeline(
                segments: transcript.segments,
                duration: max(player.duration, transcript.duration),
                time: scrubTime ?? player.currentTime,
                onScrub: { scrubTime = $0 },
                onCommit: { time in
                    player.seek(to: time)
                    scrubTime = nil
                }
            )
            .frame(height: 22)

            Text(TranscriptFormatter.timestamp(max(player.duration, transcript.duration)))
                .frame(minWidth: 40, alignment: .leading)

            Button(action: player.cycleRate) {
                Text(rateLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(width: 40, height: 24)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Playback speed")
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 720)
        .glassBackground(in: Capsule())
    }

    private var rateLabel: String {
        let rate = player.rate
        return rate == rate.rounded() ? "\(Int(rate))×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Speech drawn as colored blocks per speaker along the timeline, with a draggable playhead.
struct SpeakerTimeline: View {
    let segments: [Segment]
    let duration: TimeInterval
    let time: TimeInterval
    let onScrub: (TimeInterval) -> Void
    let onCommit: (TimeInterval) -> Void
    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let barHeight: CGFloat = isHovered ? 12 : 8
            Canvas { context, size in
                let y = (size.height - barHeight) / 2
                let track = Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: barHeight), cornerRadius: barHeight / 2)
                context.fill(track, with: .color(.primary.opacity(0.08)))
                guard duration > 0 else { return }
                context.clip(to: track)
                for segment in segments {
                    let x = segment.start / duration * size.width
                    let w = max(1.5, (segment.end - segment.start) / duration * size.width)
                    let rect = CGRect(x: x, y: y, width: w, height: barHeight)
                    let played = segment.start <= time
                    let color = segment.speaker.map(Theme.color(for:)) ?? .accentColor
                    context.fill(Path(rect), with: .color(color.opacity(played ? 0.95 : 0.4)))
                }
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: isHovered ? 22 : 18)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .offset(x: duration > 0 ? min(width - 3, max(0, time / duration * width - 1.5)) : 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub(timeAt($0.location.x, width: width)) }
                    .onEnded { onCommit(timeAt($0.location.x, width: width)) }
            )
            .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
        }
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue(TranscriptFormatter.timestamp(time))
    }

    private func timeAt(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(max(0, x / width), 1) * duration
    }
}
