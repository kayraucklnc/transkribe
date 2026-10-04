import SwiftUI
import TranskribeCore

struct PlayerBar: View {
    @Environment(PlayerController.self) private var player
    @State private var scrubTime: Double?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause" : "Play")

            Text(TranscriptFormatter.timestamp(scrubTime ?? player.currentTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubTime ?? player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 0.1)
            ) { editing in
                if !editing, let time = scrubTime {
                    player.seek(to: time)
                    scrubTime = nil
                }
            }
            .controlSize(.small)

            Text(TranscriptFormatter.timestamp(player.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
