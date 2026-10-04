import AppKit
import ApplicationServices
import TranskribeCore

/// Puts dictated text where the cursor is, or on the clipboard when there's nowhere to type.
@MainActor
enum TextInserter {
    enum Result { case pasted, copied }

    /// Accessibility lets Transkribe see the focused field and press ⌘V for you.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func insert(_ text: String) async -> Result {
        guard isTrusted, focusedFieldAcceptsText() else {
            copy(text)
            return .copied
        }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        copy(text)
        let ourChange = pasteboard.changeCount
        pressCommandV()
        // Give the target app time to read the clipboard, then put back what was there.
        try? await Task.sleep(for: .milliseconds(450))
        if pasteboard.changeCount == ourChange, !saved.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
        return .pasted
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func focusedFieldAcceptsText() -> Bool {
        if let app = NSWorkspace.shared.frontmostApplication {
            // Electron and Chromium only expose their text fields once asked to.
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let focused = value as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &role)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable)
        var ancestor: CFTypeRef?
        let hasAncestor = AXUIElementCopyAttributeValue(focused, "AXEditableAncestor" as CFString, &ancestor) == .success && ancestor != nil
        return PasteTarget.isEditable(role: role as? String, valueSettable: settable.boolValue, hasEditableAncestor: hasAncestor)
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(9)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }
}
