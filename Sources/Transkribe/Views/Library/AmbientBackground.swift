import SwiftUI

/// A soft, static mesh of color behind the library: depth without distraction or CPU cost.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.canvas
            if #available(macOS 15, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                    colors: scheme == .dark ? Self.dark : Self.light
                )
                .opacity(scheme == .dark ? 0.9 : 0.75)
            } else {
                LinearGradient(colors: scheme == .dark ? [Self.dark[0], Self.dark[8]] : [Self.light[0], Self.light[8]],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // Fade into the plain canvas lower down so the cards sit on a calm surface.
            LinearGradient(colors: [.clear, Theme.canvas], startPoint: .init(x: 0.5, y: 0.25), endPoint: .init(x: 0.5, y: 0.75))
        }
        .ignoresSafeArea()
    }

    private static let dark: [Color] = [
        Color(red: 0.23, green: 0.10, blue: 0.20), Color(red: 0.12, green: 0.09, blue: 0.24), Color(red: 0.05, green: 0.12, blue: 0.24),
        Color(red: 0.16, green: 0.07, blue: 0.13), Color(red: 0.09, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.10, blue: 0.17),
        Color(red: 0.08, green: 0.08, blue: 0.10), Color(red: 0.08, green: 0.08, blue: 0.10), Color(red: 0.08, green: 0.08, blue: 0.10),
    ]
    private static let light: [Color] = [
        Color(red: 1.00, green: 0.88, blue: 0.90), Color(red: 0.93, green: 0.89, blue: 1.00), Color(red: 0.86, green: 0.93, blue: 1.00),
        Color(red: 1.00, green: 0.94, blue: 0.94), Color(red: 0.97, green: 0.95, blue: 1.00), Color(red: 0.93, green: 0.97, blue: 1.00),
        Color(red: 0.97, green: 0.97, blue: 0.98), Color(red: 0.97, green: 0.97, blue: 0.98), Color(red: 0.97, green: 0.97, blue: 0.98),
    ]
}
