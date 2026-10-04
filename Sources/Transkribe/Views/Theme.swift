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
