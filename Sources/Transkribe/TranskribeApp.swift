import AppKit
import SwiftUI
import TranskribeCore

@main
struct TranskribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Transkribe", id: "main") {
            RootView()
                .environment(delegate.dictation)
                .environment(delegate.model)
                .environment(delegate.player)
                .environment(delegate.ai)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified(showsTitle: false))
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

        Settings {
            SettingsView()
                .environment(delegate.dictation)
                .environment(delegate.ai)
                .environment(delegate.model)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(delegate.model)
                .environment(delegate.dictation)
        } label: {
            MenuBarLabel()
                .environment(delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model: AppModel = {
        // Carry settings over from the old identifier before the model reads them.
        IdentifierMigration.migrateDefaults()
        return AppModel()
    }()
    @MainActor let player = PlayerController()
    @MainActor lazy var ai = AIService(model: model)
    @MainActor lazy var dictation = DictationController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            dictation.installShortcut()
            dictation.warmUp()
        }
    }

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
