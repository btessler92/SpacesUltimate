import AppKit
import XCTest
@testable import SpacesUltimate

final class MenuBarInteractionTests: XCTestCase {
    func testRightClickTogglesNotesOverlay() {
        XCTAssertEqual(
            MenuBarClickIntent.resolve(eventType: .rightMouseDown, modifierFlags: []),
            .toggleNotesOverlay
        )
        XCTAssertEqual(
            MenuBarClickIntent.resolve(eventType: .rightMouseUp, modifierFlags: []),
            .toggleNotesOverlay
        )
    }

    func testControlClickTogglesNotesOverlay() {
        XCTAssertEqual(
            MenuBarClickIntent.resolve(eventType: .leftMouseDown, modifierFlags: [.control]),
            .toggleNotesOverlay
        )
        XCTAssertEqual(
            MenuBarClickIntent.resolve(eventType: .leftMouseUp, modifierFlags: [.control]),
            .toggleNotesOverlay
        )
    }

    func testLeftClickKeepsExistingMenuBehavior() {
        XCTAssertEqual(
            MenuBarClickIntent.resolve(eventType: .leftMouseUp, modifierFlags: []),
            .showMenu
        )
        XCTAssertEqual(
            MenuBarClickIntent.resolve(eventType: nil, modifierFlags: []),
            .showMenu
        )
    }
}
