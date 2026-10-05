import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts via Carbon, which needs no Accessibility permission and
/// swallows the key so the frontmost app never sees it.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    private var actions: [UInt32: () -> Void] = [:]
    private var releaseActions: [UInt32: () -> Void] = [:]
    /// Held keys auto-repeat; only the first press counts until the key is released.
    private var held: Set<UInt32> = []
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var isInstalled = false

    /// Returns a token for `unregister`, or nil if the shortcut couldn't be claimed.
    func register(keyCode: Int, modifiers: Int, onRelease: (() -> Void)? = nil, action: @escaping () -> Void) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x544B_4252), id: id) // "TKBR"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        references[id] = reference
        actions[id] = action
        releaseActions[id] = onRelease
        return id
    }

    func unregister(_ id: UInt32?) {
        guard let id, let reference = references.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reference)
        actions[id] = nil
        releaseActions[id] = nil
        held.remove(id)
    }

    fileprivate func fire(_ id: UInt32, pressed: Bool) {
        if pressed {
            guard held.insert(id).inserted else { return }
            actions[id]?()
        } else {
            held.remove(id)
            releaseActions[id]?()
        }
    }

    private func installHandler() {
        guard !isInstalled else { return }
        isInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.shared.fire(id, pressed: pressed) } }
            return noErr
        }, 2, &specs, nil, nil)
    }
}
