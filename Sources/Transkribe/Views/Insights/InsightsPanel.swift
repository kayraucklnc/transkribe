import SwiftUI
import TranskribeCore

/// Placeholder until the AI layer lands: shows talk-time structure.
struct InsightsPanel: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights").font(.title3.weight(.bold))
            Spacer()
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
