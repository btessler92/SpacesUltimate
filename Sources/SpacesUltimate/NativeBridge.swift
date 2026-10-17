import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
final class NativeBridge {
    private(set) var lastSwitchAttempt = "No switch attempted yet"

    func switchToSpace(_ space: SpaceMetadata, from currentOrderIndex: Int? = nil) -> Bool {
        guard AXIsProcessTrusted() else {
            lastSwitchAttempt = "Accessibility permission is not granted for \(AppIdentity.permissionTargetSummary); macOS may ignore automated Space switching."
            AppLog.shared.warning(lastSwitchAttempt)
            return false
        }

        let shortcutText = space.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shortcutText.isEmpty {
            guard let shortcut = KeyboardShortcut.parse(shortcutText) else {
                lastSwitchAttempt = "Could not understand configured shortcut '\(space.shortcut)'. Use a format like Control+Option+1 or Command+Shift+Right."
                AppLog.shared.warning(lastSwitchAttempt)
                return false
            }
            let success = sendShortcut(shortcut)
            lastSwitchAttempt = success
                ? "Sent configured shortcut \(shortcut.displayName) for Desktop \(space.orderIndex)."
                : "Could not create keyboard events for configured shortcut \(shortcut.displayName)."
            if success {
                AppLog.shared.info(lastSwitchAttempt)
            } else {
                AppLog.shared.warning(lastSwitchAttempt)
            }
            return success
        }

        if let currentOrderIndex, currentOrderIndex == space.orderIndex {
            lastSwitchAttempt = "Already on Desktop \(space.orderIndex)."
            AppLog.shared.info(lastSwitchAttempt)
            return true
        }

        if let currentOrderIndex {
            let offset = space.orderIndex - currentOrderIndex
            let success = sendRelativeSpaceMove(offset)
            lastSwitchAttempt = success
                ? "Sent Control+\(offset > 0 ? "Right" : "Left") \(abs(offset)) time(s) from Desktop \(currentOrderIndex) toward Desktop \(space.orderIndex)."
                : "Could not create relative Space-switch keyboard events from Desktop \(currentOrderIndex) to Desktop \(space.orderIndex)."
            if success {
                AppLog.shared.info(lastSwitchAttempt)
            } else {
                AppLog.shared.warning(lastSwitchAttempt)
            }
            return success
        }

        guard (1...9).contains(space.orderIndex) else {
            lastSwitchAttempt = "Desktop \(space.orderIndex) is outside Control+number fallback range."
            AppLog.shared.warning(lastSwitchAttempt)
            return false
        }

        let success = sendControlNumber(space.orderIndex)
        lastSwitchAttempt = success
            ? "Sent Control+\(space.orderIndex) for Desktop \(space.orderIndex)"
            : "Could not create keyboard events for Control+\(space.orderIndex)"
        if success {
            AppLog.shared.info(lastSwitchAttempt)
        } else {
            AppLog.shared.warning(lastSwitchAttempt)
        }
        return success
    }

    private func sendRelativeSpaceMove(_ offset: Int) -> Bool {
        guard offset != 0 else { return true }
        let keyCode = offset > 0 ? CGKeyCode(kVK_RightArrow) : CGKeyCode(kVK_LeftArrow)
        for _ in 0..<abs(offset) {
            guard sendControlKey(keyCode) else { return false }
            Thread.sleep(forTimeInterval: 0.08)
        }
        return true
    }

    private func sendControlNumber(_ number: Int) -> Bool {
        guard let keyCode = Self.keyCodes[number] else {
            return false
        }
        return sendControlKey(keyCode)
    }

    private func sendShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        sendKey(shortcut.keyCode, flags: shortcut.flags)
    }

    private func sendControlKey(_ keyCode: CGKeyCode) -> Bool {
        sendKey(keyCode, flags: .maskControl)
    }

    private func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static let keyCodes: [Int: CGKeyCode] = [
        1: CGKeyCode(kVK_ANSI_1),
        2: CGKeyCode(kVK_ANSI_2),
        3: CGKeyCode(kVK_ANSI_3),
        4: CGKeyCode(kVK_ANSI_4),
        5: CGKeyCode(kVK_ANSI_5),
        6: CGKeyCode(kVK_ANSI_6),
        7: CGKeyCode(kVK_ANSI_7),
        8: CGKeyCode(kVK_ANSI_8),
        9: CGKeyCode(kVK_ANSI_9)
    ]
}
