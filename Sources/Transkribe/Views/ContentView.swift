import SwiftUI
import TranskribeCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let transcript = model.selectedTranscript {
                TranscriptView(transcript: transcript)
                    .id(transcript.id)
            } else {
                WelcomeView()
            }
        }
        .searchable(text: $model.query, placement: .sidebar, prompt: "Search transcripts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RecordToolbarControl()
            }
        }
        .overlay {
            if isDropTargeted { DropOverlay() }
        }
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
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .padding(16)
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 44, weight: .light))
                Text("Drop to transcribe")
                    .font(.title2.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
