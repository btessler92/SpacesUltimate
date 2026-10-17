import Carbon
import CoreGraphics
import AppKit
import Foundation

struct KeyboardShortcut: Equatable {
    var displayName: String
    var keyCode: CGKeyCode
    var flags: CGEventFlags

    var eventModifierFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    var carbonModifierFlags: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskControl) { result |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
        if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
        if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
        return result
    }

    func matches(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.keyCode == keyCode && event.modifierFlags.intersection(relevant) == eventModifierFlags
    }

    static func parse(_ rawValue: String) -> KeyboardShortcut? {
        let tokens = rawValue
            .replacingOccurrences(of: "⌘", with: "+cmd+")
            .replacingOccurrences(of: "⌥", with: "+option+")
            .replacingOccurrences(of: "⌃", with: "+control+")
            .replacingOccurrences(of: "⇧", with: "+shift+")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: " ", with: "+")
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        var flags: CGEventFlags = []
        var keyToken: String?
        for token in tokens {
            switch token {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "opt", "option", "alt":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            default:
                guard keyToken == nil else { return nil }
                keyToken = token
            }
        }

        guard let keyToken,
              let keyCode = keyCodes[keyToken] else {
            return nil
        }

        return KeyboardShortcut(displayName: normalizedDisplayName(flags: flags, keyToken: keyToken), keyCode: keyCode, flags: flags)
    }

    private static func normalizedDisplayName(flags: CGEventFlags, keyToken: String) -> String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("Control") }
        if flags.contains(.maskAlternate) { parts.append("Option") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Command") }
        parts.append(displayKeyNames[keyToken] ?? keyToken.uppercased())
        return parts.joined(separator: "+")
    }

    private static let displayKeyNames: [String: String] = [
        "left": "Left",
        "right": "Right",
        "up": "Up",
        "down": "Down",
        "space": "Space",
        "tab": "Tab",
        "return": "Return",
        "enter": "Return",
        "escape": "Escape",
        "esc": "Escape"
    ]

    private static let keyCodes: [String: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "0": CGKeyCode(kVK_ANSI_0),
        "1": CGKeyCode(kVK_ANSI_1),
        "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4),
        "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7),
        "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
        "left": CGKeyCode(kVK_LeftArrow),
        "right": CGKeyCode(kVK_RightArrow),
        "up": CGKeyCode(kVK_UpArrow),
        "down": CGKeyCode(kVK_DownArrow),
        "space": CGKeyCode(kVK_Space),
        "tab": CGKeyCode(kVK_Tab),
        "return": CGKeyCode(kVK_Return),
        "enter": CGKeyCode(kVK_Return),
        "escape": CGKeyCode(kVK_Escape),
        "esc": CGKeyCode(kVK_Escape)
    ]
}
