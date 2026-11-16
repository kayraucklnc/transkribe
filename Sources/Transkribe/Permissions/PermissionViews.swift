import SwiftUI
import TranskribeCore

/// One card per permission, each with the one button that moves it forward.
struct PermissionList: View {
    @Environment(PermissionCenter.self) private var center

    var body: some View {
        VStack(spacing: 12) {
            ForEach(center.items) { item in
                PermissionRow(item: item)
            }
        }
        .task {
            // Permissions change in System Settings; notice as soon as the user comes back.
            while !Task.isCancelled {
                center.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct PermissionRow: View {
    @Environment(PermissionCenter.self) private var center
    let item: PermissionCenter.Item
    @State private var isAsking = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(item.tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text(item.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.state == .needsReopen {
                    Text("Turned it on in System Settings? Reopen Transkribe so macOS applies it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Stage.hairline, lineWidth: 1))
        .animation(.spring(response: 0.35), value: item.state)
    }

    @ViewBuilder
    private var actions: some View {
        switch item.state {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.semibold))
                .transition(.scale.combined(with: .opacity))
        case .notAsked:
            Button("Allow", action: ask)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAsking)
        case .denied:
            Button("Open Settings") { center.openSettings(item.kind) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .needsReopen:
            VStack(alignment: .trailing, spacing: 6) {
                Button("Reopen", action: center.reopen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Open Settings") { center.openSettings(item.kind) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.caption.weight(.medium))
            }
        }
    }

    private func ask() {
        isAsking = true
        Task {
            await center.request(item.kind)
            isAsking = false
        }
    }
}

/// Shown over the app at launch when a permission is missing (turned off since setup, or never
/// given). It goes away by itself once everything is allowed.
struct PermissionsGate: View {
    @Environment(PermissionCenter.self) private var center

    var body: some View {
        ZStack {
            StageBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transkribe needs a few permissions")
                            .font(.system(size: 32, weight: .bold))
                            .tracking(-0.6)
                        Text("Some are missing or were turned off. Allow them to keep using Transkribe. Everything still stays on this Mac.")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    PermissionList()
                }
                .frame(maxWidth: 620)
                .padding(40)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
