import AppKit
import XCTest
@testable import SpacesUltimate

final class MissionControlMonitorTests: XCTestCase {
    func testDraggingDoesNotEndMissionControlWhileDockWindowsAreReplaced() {
        var state = MissionControlSessionState()
        XCTAssertEqual(state.observe(true), true)
        for _ in 0..<5 {
            XCTAssertNil(state.observe(false, mouseIsPressed: true))
            XCTAssertTrue(state.isActive)
        }
        XCTAssertNil(state.observe(true))
        XCTAssertTrue(state.isActive)
    }

    func testRealExitIsConfirmedAfterMouseRelease() {
        var state = MissionControlSessionState()
        XCTAssertEqual(state.observe(true), true)
        XCTAssertNil(state.observe(false))
        XCTAssertNil(state.observe(false, mouseIsPressed: true))
        XCTAssertNil(state.observe(false))
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.observe(false), false)
        XCTAssertFalse(state.isActive)
    }

    func testShowsOncePerSessionAndRearmsAfterExit() {
        var state = MissionControlSessionState()
        XCTAssertNil(state.observe(false))
        XCTAssertEqual(state.observe(true), true)
        // Polling after an outside click must not reopen the overlay.
        XCTAssertNil(state.observe(true))
        XCTAssertNil(state.observe(true))
        XCTAssertNil(state.observe(false))
        XCTAssertEqual(state.observe(false), false)
        XCTAssertEqual(state.observe(true), true)
    }

    func testTransientOrUnavailableSamplesDoNotEndSession() {
        var state = MissionControlSessionState()
        XCTAssertEqual(state.observe(true), true)
        XCTAssertNil(state.observe(false))
        XCTAssertNil(state.observe(true))
        XCTAssertNil(state.observe(false))
        XCTAssertNil(state.observe(nil))
        XCTAssertNil(state.observe(false))
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.observe(false), false)
    }

    func testDetectsSecondaryDisplayWithoutNamesOrSharingState() {
        let secondary = CGRect(x: -1080, y: -690, width: 1080, height: 1920)
        XCTAssertTrue(MissionControlWindowDetection.isActive(
            windows: [window(pid: 42, layer: 18, bounds: secondary)],
            dockPIDs: [42], screenBounds: [primary, secondary]
        ))
    }

    func testRejectsNormalDockOtherAppsAndSmallDockWindows() {
        XCTAssertFalse(MissionControlWindowDetection.isActive(
            windows: [
                window(pid: 42, layer: 20, bounds: primary),
                window(pid: 84, layer: 18, bounds: primary),
                window(pid: 42, layer: 18, bounds: CGRect(x: 0, y: 0, width: 300, height: 80)),
                [:]
            ],
            dockPIDs: [42], screenBounds: [primary]
        ))
    }

    private let primary = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    private func window(pid: Int, layer: Int, bounds: CGRect) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: bounds.dictionaryRepresentation
        ]
    }
}
