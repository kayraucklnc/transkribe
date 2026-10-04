import Foundation

/// A keyboard shortcut: a virtual key code plus Carbon modifier flags.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public static let command = 0x100
    public static let shift = 0x200
    public static let option = 0x800
    public static let control = 0x1000

    public var keyCode: Int
    public var modifiers: Int
    /// What the key prints on the user's keyboard layout, captured when it was recorded.
    public var character: String?

    public init(keyCode: Int, modifiers: Int, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }

    public static let optionSpace = KeyCombo(keyCode: 49, modifiers: option)

    /// Shift alone isn't enough: ⇧Space or ⇧A would fire while typing.
    public var isValid: Bool {
        let meaningful = modifiers & (Self.command | Self.option | Self.control)
        return meaningful != 0 || Self.functionKeys[keyCode] != nil
    }

    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        let key = keyName
        return key.count > 1 && !text.isEmpty ? "\(text) \(key)" : text + key
    }

    public var keyName: String {
        if let name = Self.functionKeys[keyCode] ?? Self.namedKeys[keyCode] { return name }
        return character?.uppercased() ?? "Key \(keyCode)"
    }

    static let namedKeys: [Int: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]
}
