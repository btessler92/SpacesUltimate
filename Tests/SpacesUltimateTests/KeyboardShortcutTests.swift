import CoreGraphics
import XCTest
@testable import SpacesUltimate

final class KeyboardShortcutTests: XCTestCase {
    func testParsesCommonModifierShortcut() {
        let shortcut = KeyboardShortcut.parse("Control+Option+1")

        XCTAssertEqual(shortcut?.displayName, "Control+Option+1")
        XCTAssertTrue(shortcut?.flags.contains(.maskControl) == true)
        XCTAssertTrue(shortcut?.flags.contains(.maskAlternate) == true)
    }

    func testParsesSymbolShortcut() {
        let shortcut = KeyboardShortcut.parse("⌘ ⇧ right")

        XCTAssertEqual(shortcut?.displayName, "Shift+Command+Right")
        XCTAssertTrue(shortcut?.flags.contains(.maskCommand) == true)
        XCTAssertTrue(shortcut?.flags.contains(.maskShift) == true)
    }

    func testRejectsUnknownKey() {
        XCTAssertNil(KeyboardShortcut.parse("Control+Banana"))
    }

    func testRejectsMultipleKeys() {
        XCTAssertNil(KeyboardShortcut.parse("Control+A+B"))
    }
}
