import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts via Carbon, which needs no Accessibility permission and
/// swallows the key so the frontmost app never sees it.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    private var actions: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var isInstalled = false

    /// Returns a token for `unregister`, or nil if the shortcut couldn't be claimed.
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x544B_4252), id: id) // "TKBR"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        references[id] = reference
        actions[id] = action
        return id
    }

    func unregister(_ id: UInt32?) {
        guard let id, let reference = references.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reference)
        actions[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandler() {
        guard !isInstalled else { return }
        isInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// The shortcut that opens dictation, picked in Settings.
enum DictationShortcut: String, CaseIterable, Identifiable, Codable {
    case optionSpace
    case controlOptionSpace
    case commandShiftSpace
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlOptionSpace: "⌃⌥ Space"
        case .commandShiftSpace: "⇧⌘ Space"
        case .off: "Off"
        }
    }

    var modifiers: Int? {
        switch self {
        case .optionSpace: optionKey
        case .controlOptionSpace: optionKey | controlKey
        case .commandShiftSpace: cmdKey | shiftKey
        case .off: nil
        }
    }

    static let keyCode = kVK_Space
}
