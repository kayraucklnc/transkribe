import SwiftUI
import TranskribeCore

enum Theme {
    /// Calm, distinguishable speaker colors. "Me" always gets the first one.
    static let speakerColors: [Color] = [
        Color(red: 0.25, green: 0.52, blue: 0.96), // blue
        Color(red: 0.96, green: 0.55, blue: 0.20), // orange
        Color(red: 0.20, green: 0.72, blue: 0.49), // green
        Color(red: 0.86, green: 0.33, blue: 0.62), // pink
        Color(red: 0.55, green: 0.42, blue: 0.93), // purple
        Color(red: 0.13, green: 0.68, blue: 0.78), // teal
        Color(red: 0.88, green: 0.70, blue: 0.16), // yellow
        Color(red: 0.89, green: 0.33, blue: 0.29), // red
    ]

    static func color(for speaker: Int?) -> Color {
        guard let speaker else { return .secondary }
        return speakerColors[speaker % speakerColors.count]
    }

    static let record = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

extension View {
    /// Liquid Glass on macOS 26, a material capsule before that.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
    }
}

/// Colored circle with the speaker's initial.
struct SpeakerAvatar: View {
    let name: String
    let speaker: Int
    var size: CGFloat = 22

    var body: some View {
        // Default names ("Speaker 2") show the number; real names show their initial.
        let label = name == "Speaker \(speaker)" ? "\(speaker)" : String(name.prefix(1)).uppercased()
        Text(label)
            .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.color(for: speaker).gradient, in: Circle())
    }
}

extension Color {
    /// A color that differs between light and dark appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }
}

extension Theme {
    /// iMessage-like bubble fills.
    static let myBubble = LinearGradient(
        colors: [Color(red: 0.16, green: 0.56, blue: 1.0), Color(red: 0.04, green: 0.45, blue: 0.98)],
        startPoint: .top, endPoint: .bottom
    )
    static let theirBubble = Color(
        light: NSColor(red: 0.914, green: 0.914, blue: 0.922, alpha: 1),
        dark: NSColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1)
    )
    static let card = Color(
        light: NSColor(white: 1, alpha: 1),
        dark: NSColor(white: 0.16, alpha: 1)
    )
    static let canvas = Color(
        light: NSColor(red: 0.965, green: 0.965, blue: 0.972, alpha: 1),
        dark: NSColor(red: 0.105, green: 0.105, blue: 0.115, alpha: 1)
    )
}

/// Overlapping avatars for a conversation's participants.
struct AvatarStack: View {
    let transcript: Transcript
    var size: CGFloat = 22
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(transcript.speakers.prefix(limit)), id: \.self) { speaker in
                SpeakerAvatar(name: transcript.name(of: speaker), speaker: speaker, size: size)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
            }
        }
    }
}

/// Tiny "who spoke when" strip.
struct SpeakerStrip: View {
    let segments: [Segment]
    let duration: TimeInterval
    var height: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.fill(track, with: .color(.primary.opacity(0.07)))
            guard duration > 0 else { return }
            context.clip(to: track)
            for segment in segments {
                let x = segment.start / duration * size.width
                let width = max(1, (segment.end - segment.start) / duration * size.width)
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                             with: .color(segment.speaker.map(Theme.color(for:)) ?? .accentColor))
            }
        }
        .frame(height: height)
    }
}
