import AppKit
import Carbon.HIToolbox

/// A persistable global keyboard chord for opening Quick Look.
struct QuickAccessShortcut: Codable, Equatable, Hashable, Sendable {
    static let defaultShortcut = QuickAccessShortcut(
        keyCode: UInt32(kVK_ANSI_U),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "U"
    )

    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyLabel: String

    /// A compact macOS-style representation such as `⇧⌘U`.
    var displayName: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 {
            result += "⌃"
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            result += "⌥"
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            result += "⇧"
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            result += "⌘"
        }
        return result + keyLabel
    }

    /// Creates a safe global shortcut from a keyboard event.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            return nil
        }

        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }

        let keyCode = UInt32(event.keyCode)
        let characters = event.charactersIgnoringModifiers ?? ""
        self.init(
            keyCode: keyCode,
            carbonModifiers: modifiers,
            keyLabel: Self.label(for: keyCode, characters: characters)
        )
    }

    private init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    private static func label(for keyCode: UInt32, characters: String) -> String {
        let functionKeyLabels = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
        ]
        if let functionKeyLabel = functionKeyLabels[Int(keyCode)] {
            return functionKeyLabel
        }

        return switch Int(keyCode) {
        case kVK_Return:
            "↩"
        case kVK_Tab:
            "⇥"
        case kVK_Space:
            "Space"
        case kVK_Delete:
            "⌫"
        case kVK_ForwardDelete:
            "⌦"
        case kVK_LeftArrow:
            "←"
        case kVK_RightArrow:
            "→"
        case kVK_DownArrow:
            "↓"
        case kVK_UpArrow:
            "↑"
        default:
            characters.uppercased()
        }
    }
}

/// One or two modified chords pressed in order to toggle Quick Look.
struct QuickAccessShortcutSequence: Codable, Equatable, Sendable {
    static let maximumChordCount = 2
    static let defaultSequence = QuickAccessShortcutSequence(
        validatedShortcuts: [.defaultShortcut]
    )

    let shortcuts: [QuickAccessShortcut]

    var displayName: String {
        shortcuts.map(\.displayName).joined(separator: " → ")
    }

    init?(shortcuts: [QuickAccessShortcut]) {
        guard !shortcuts.isEmpty,
              shortcuts.count <= Self.maximumChordCount else {
            return nil
        }
        self.shortcuts = shortcuts
    }

    private init(validatedShortcuts: [QuickAccessShortcut]) {
        shortcuts = validatedShortcuts
    }
}
