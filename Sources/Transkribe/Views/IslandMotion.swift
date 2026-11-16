import SwiftUI

/// How the notch island moves. Growing out of the notch is quick with a hint of overshoot;
/// going back is calm and settles without a wobble. Content waits for the shape to open, and
/// leaves before it closes, so text never squeezes or spills.
enum IslandMotion {
    /// Opening up (a reminder, "Recording", "Wrap up"): lively, a little bounce.
    static let expand = Animation.spring(duration: 0.5, bounce: 0.26)
    /// Folding back toward the notch: no bounce, it just settles. It starts a beat late so the
    /// text has dissolved before the edges reach it.
    static let settle = Animation.spring(duration: 0.44, bounce: 0).delay(0.07)
    /// With Reduce Motion on: a plain, short cross-fade in size.
    static let reduced = Animation.easeInOut(duration: 0.22)

    /// The window waits this long before shrinking, so it never clips the shape mid-motion.
    static let restTime: Duration = .milliseconds(800)

    /// Text and buttons fade up out of a soft blur once the island has started to open,
    /// and fade out quickly before it folds away.
    static var content: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .top))
                .combined(with: .offset(y: -4))
                .combined(with: .modifier(active: Blur(radius: 6), identity: Blur(radius: 0)))
                .animation(.easeOut(duration: 0.3).delay(0.1)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .combined(with: .modifier(active: Blur(radius: 4), identity: Blur(radius: 0)))
                .animation(.easeIn(duration: 0.09))
        )
    }

    /// The dot and timer beside the notch.
    static var wings: AnyTransition {
        .opacity
            .combined(with: .modifier(active: Blur(radius: 3), identity: Blur(radius: 0)))
            .animation(.easeOut(duration: 0.25).delay(0.08))
    }

    static func animation(from old: NotchHUD.Mode, to new: NotchHUD.Mode, in geometry: NotchGeometry,
                          reduceMotion: Bool) -> Animation {
        if reduceMotion { return reduced }
        let before = geometry.size(for: old), after = geometry.size(for: new)
        let grows = after.height > before.height || (after.height == before.height && after.width > before.width)
        return grows ? expand : settle
    }

    private struct Blur: ViewModifier {
        let radius: CGFloat
        func body(content: Content) -> some View { content.blur(radius: radius) }
    }
}

/// An icon that pops in with a small spring when its card appears.
struct PopIn: ViewModifier {
    var delay: Double = 0.14
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.55)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.45).delay(delay)) { shown = true }
            }
    }
}
