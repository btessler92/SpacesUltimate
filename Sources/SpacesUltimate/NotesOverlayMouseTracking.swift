import AppKit

enum NotesOverlayMouseLocation {
    static func isOnScreen(_ point: NSPoint, screenFrames: [NSRect]) -> Bool {
        screenFrames.contains { $0.contains(point) }
    }
}

/// Quartz activity counters also advance for clicks consumed by Dock's Mission Control UI.
/// Reading them does not require Accessibility or an event tap, and does not intercept input.
struct NotesOverlayMouseSnapshot {
    var downCounts: [UInt32]
    var pressedButtons: Int

    @MainActor
    static func current() -> Self {
        Self(
            downCounts: [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].map {
                CGEventSource.counterForEventType(.combinedSessionState, eventType: $0)
            },
            pressedButtons: NSEvent.pressedMouseButtons
        )
    }
}

struct NotesOverlayMouseTracking {
    private var previous: NotesOverlayMouseSnapshot?

    mutating func synchronize(_ snapshot: NotesOverlayMouseSnapshot) {
        previous = snapshot
    }

    mutating func newPresses(in snapshot: NotesOverlayMouseSnapshot) -> [Int] {
        defer { previous = snapshot }
        guard let previous else { return [] }
        return (0..<3).filter { button in
            let counterChanged = snapshot.downCounts[button] != previous.downCounts[button]
            let newlyPressed = snapshot.pressedButtons & ~previous.pressedButtons & (1 << button) != 0
            return counterChanged || newlyPressed
        }
    }
}

struct NotesOverlayMousePress {
    let button: Int
    let downCount: UInt32

    init(button: Int, snapshot: NotesOverlayMouseSnapshot) {
        self.button = min(max(button, 0), 2)
        self.downCount = snapshot.downCounts[self.button]
    }

    func matches(button: Int, snapshot: NotesOverlayMouseSnapshot) -> Bool {
        self.button == min(max(button, 0), 2) && downCount == snapshot.downCounts[self.button]
    }
}
