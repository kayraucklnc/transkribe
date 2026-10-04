import SwiftUI
import TranskribeCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 380)
        } detail: {
            ZStack(alignment: .bottom) {
                if let transcript = model.selectedTranscript {
                    TranscriptView(transcript: transcript)
                        .id(transcript.id)
                        .transition(.opacity)
                } else {
                    HomeView()
                        .transition(.opacity)
                }
                if model.isRecording, model.selection != nil {
                    RecordingCapsule()
                        .padding(.bottom, 80)
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
        }
        .searchable(text: $model.query, placement: .sidebar, prompt: "Search")
        .toolbar {
            if model.selection != nil, !model.isRecording {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.selection = nil
                    } label: {
                        Label("New Recording", systemImage: "plus")
                    }
                    .help("New recording")
                }
            }
        }
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
        .onAppear { columns = model.transcripts.isEmpty ? .detailOnly : .all }
        .onChange(of: model.transcripts.isEmpty) { _, isEmpty in
            withAnimation(Theme.spring) { columns = isEmpty ? .detailOnly : .all }
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))
                .padding(14)
            VStack(spacing: 14) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 54, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(pulse ? 1.06 : 1)
                Text("Drop to transcribe")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Any audio or video. Any language.")
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
