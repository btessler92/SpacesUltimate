import AppKit
import XCTest
@testable import SpacesUltimate

final class NotesOverlayMouseTrackingTests: XCTestCase {
    func testSyntheticOffscreenPressDoesNotCountAsAnOutsideClick() {
        let screens = [NSRect(x: 0, y: 0, width: 2560, height: 1440),
                       NSRect(x: -1080, y: 210, width: 1080, height: 1920)]
        XCTAssertFalse(NotesOverlayMouseLocation.isOnScreen(NSPoint(x: -1, y: -1), screenFrames: screens))
        XCTAssertTrue(NotesOverlayMouseLocation.isOnScreen(NSPoint(x: 100, y: 1240), screenFrames: screens))
        XCTAssertTrue(NotesOverlayMouseLocation.isOnScreen(NSPoint(x: -600, y: 1930), screenFrames: screens))
        // Negative coordinates are legitimate when a display is arranged below the main display.
        XCTAssertTrue(NotesOverlayMouseLocation.isOnScreen(NSPoint(x: -1, y: -1),
            screenFrames: [NSRect(x: -1080, y: -1920, width: 1080, height: 1920)]))
    }

    func testDetectsClickConsumedByMissionControlWithoutAnNSEvent() {
        var tracking = NotesOverlayMouseTracking()
        tracking.synchronize(snapshot(left: 100))
        // A full press and release can happen between samples; button state alone misses it.
        XCTAssertEqual(tracking.newPresses(in: snapshot(left: 101)), [0])
        XCTAssertEqual(tracking.newPresses(in: snapshot(left: 101)), [])
    }

    func testOpeningClickAndButtonReleaseDoNotDismissNewOverlay() {
        var tracking = NotesOverlayMouseTracking()
        tracking.synchronize(snapshot(left: 100, pressed: 1))
        XCTAssertEqual(tracking.newPresses(in: snapshot(left: 100, pressed: 1)), [])
        XCTAssertEqual(tracking.newPresses(in: snapshot(left: 100)), [])
    }

    func testAppKitClickIsNotReprocessedAtALaterCursorPosition() {
        var tracking = NotesOverlayMouseTracking()
        tracking.synchronize(snapshot(left: 100))
        // The local monitor handled this click with its exact event position.
        tracking.synchronize(snapshot(left: 101))
        XCTAssertEqual(tracking.newPresses(in: snapshot(left: 101)), [])
    }

    func testTracksRightAndOtherButtonsAndCounterWrap() {
        var tracking = NotesOverlayMouseTracking()
        tracking.synchronize(NotesOverlayMouseSnapshot(downCounts: [.max, 20, 30], pressedButtons: 0))
        XCTAssertEqual(tracking.newPresses(in: NotesOverlayMouseSnapshot(downCounts: [0, 21, 31], pressedButtons: 0)), [0, 1, 2])
    }

    func testButtonStateDetectsPressBeforeCounterUpdates() {
        var tracking = NotesOverlayMouseTracking()
        tracking.synchronize(snapshot(left: 100))
        XCTAssertEqual(tracking.newPresses(in: snapshot(left: 100, pressed: 1)), [0])
    }

    func testMenuMouseUpDoesNotReopenNotesDismissedByTheSameRightClick() {
        let down = NotesOverlayMouseSnapshot(downCounts: [100, 21, 30], pressedButtons: 2)
        let outsidePress = NotesOverlayMousePress(button: 1, snapshot: down)
        let up = NotesOverlayMouseSnapshot(downCounts: [100, 21, 30], pressedButtons: 0)
        XCTAssertTrue(outsidePress.matches(button: 1, snapshot: up))
        let nextClick = NotesOverlayMouseSnapshot(downCounts: [100, 22, 30], pressedButtons: 0)
        XCTAssertFalse(outsidePress.matches(button: 1, snapshot: nextClick))
    }

    func testControlClickUsesTheLeftButtonAndDoesNotSuppressANewClick() {
        let outsidePress = NotesOverlayMousePress(button: 0, snapshot: snapshot(left: 101, pressed: 1))
        XCTAssertTrue(outsidePress.matches(button: 0, snapshot: snapshot(left: 101)))
        XCTAssertFalse(outsidePress.matches(button: 0, snapshot: snapshot(left: 102)))
        XCTAssertFalse(outsidePress.matches(button: 1, snapshot: snapshot(left: 101)))
    }

    private func snapshot(left: UInt32, pressed: Int = 0) -> NotesOverlayMouseSnapshot {
        NotesOverlayMouseSnapshot(downCounts: [left, 20, 30], pressedButtons: pressed)
    }
}
