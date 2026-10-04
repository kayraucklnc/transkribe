import SwiftUI
import TranskribeCore

/// One window, two places: the library and a conversation. No sidebar.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let transcript = model.selectedTranscript {
                ConversationView(transcript: transcript)
                    .id(transcript.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                LibraryView()
                    .transition(.opacity)
            }
            if model.isRecording, model.selection != model.liveRecordingID {
                RecordingCapsule()
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: model.selection)
        .animation(Theme.spring, value: model.isRecording)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Toast(message: toast)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: model.toast)
        .overlay {
            if isDropTargeted { DropOverlay() }
        }
        .animation(.easeOut(duration: 0.18), value: isDropTargeted)
        .onDrop(of: FileImport.acceptedTypes, isTargeted: $isDropTargeted) { providers in
            FileImport.handle(providers, model: model)
        }
        .onPasteCommand(of: FileImport.acceptedTypes) { providers in
            _ = FileImport.handle(providers, model: model)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { alert in
            if let url = alert.settingsURL {
                Button("Open System Settings") { NSWorkspace.shared.open(url) }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

private struct DropOverlay: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))
                .padding(16)
            VStack(spacing: 14) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 56, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(pulse ? 1.07 : 1)
                Text("Drop to transcribe")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Any audio or video. Any language. Any length.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
