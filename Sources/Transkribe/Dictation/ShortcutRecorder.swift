import AppKit
import Carbon.HIToolbox
import SwiftUI
import TranskribeCore

/// Click, then press any key combination to use it. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyCombo?
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pending = ""
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(size: 13, weight: isRecording ? .regular : .medium))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .frame(minWidth: 130)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 1.5 : 0.5))
                    .offset(x: rejected ? -4 : 0)
            }
            .buttonStyle(.plain)
            .help("Click, then press the keys you want")
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Turn the shortcut off")
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording { return pending.isEmpty ? "Type shortcut…" : pending }
        return shortcut?.display ?? "Record Shortcut"
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        onBegin()
        isRecording = true
        pending = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onEnd()
    }

    private func handle(_ event: NSEvent) {
        let modifiers = Self.carbon(event.modifierFlags)
        if event.type == .flagsChanged {
            // Show the modifiers as they're held, before the key arrives.
            pending = KeyCombo(keyCode: -1, modifiers: modifiers, character: "").display
            return
        }
        let code = Int(event.keyCode)
        if modifiers == 0, code == kVK_Escape { return stop() }
        if modifiers == 0, code == kVK_Delete || code == kVK_ForwardDelete {
            shortcut = nil
            return stop()
        }
        let combo = KeyCombo(keyCode: code, modifiers: modifiers, character: event.charactersIgnoringModifiers)
        guard combo.isValid else {
            NSSound.beep()
            withAnimation(.spring(response: 0.15, dampingFraction: 0.2)) { rejected = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) { rejected = false }
            return
        }
        shortcut = combo
        stop()
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= KeyCombo.command }
        if flags.contains(.shift) { result |= KeyCombo.shift }
        if flags.contains(.option) { result |= KeyCombo.option }
        if flags.contains(.control) { result |= KeyCombo.control }
        return result
    }
}
