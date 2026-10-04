import AppKit
import SwiftUI
import TranskribeCore

@main
struct TranskribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Transkribe", id: "main") {
            ContentView()
                .environment(delegate.model)
                .environment(delegate.player)
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(delegate.model.isRecording ? "Stop Recording" : "New Recording") {
                    delegate.model.toggleRecording()
                }
                .keyboardShortcut("r")
                Button("Open…") { FileImport.presentOpenPanel(model: delegate.model) }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Transcript") {
                    if let id = delegate.model.selection { delegate.model.copyText(of: id) }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(delegate.model.selection == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()
    @MainActor let player = PlayerController()

    /// Files dropped on the Dock icon or opened with "Open With → Transkribe".
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in model.importFiles(urls) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = MainActor.assumeIsolated { self.model }
        guard MainActor.assumeIsolated({ model.isRecording }) else { return .terminateNow }
        Task { @MainActor in
            await model.finishRecordingForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
