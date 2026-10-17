import AppKit
import XCTest
@testable import SpacesUltimate

final class InlineEditableNameFieldTests: XCTestCase {
    @MainActor
    func testDoubleClickStartsEditingWithoutDiscardingTheFirstClick() throws {
        _ = NSApplication.shared
        var interactions = 0
        let field = InlineEditableNameField(name: "Research", fallbackName: "Desktop 1") { _ in }
        field.onSingleClick = { interactions += 1 }
        field.onBeginEditing = { interactions += 1 }
        XCTAssertTrue(field.acceptsFirstMouse(for: nil))

        for count in 1...2 {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: count, clickCount: count, pressure: 1
            ))
            field.mouseDown(with: event)
            XCTAssertEqual(field.isEditable, count == 2)
        }
        XCTAssertEqual(interactions, 2)
        XCTAssertEqual(field.stringValue, "Research")
    }

    @MainActor
    func testRenameFinishesDisplayBeforeSavingAndCommitsOnlyOnce() throws {
        _ = NSApplication.shared
        var values: [String] = []
        var field: InlineEditableNameField!
        field = InlineEditableNameField(
            name: "Research", fallbackName: "Desktop 1", displayText: { "★ \($0)" }
        ) { value in
            XCTAssertFalse(field.isEditable)
            XCTAssertEqual(field.stringValue, "★ Writing")
            values.append(value)
        }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 2, clickCount: 2, pressure: 1
        ))
        field.mouseDown(with: event)
        field.stringValue = "Writing"
        let notification = Notification(name: NSControl.textDidEndEditingNotification, object: field)
        field.controlTextDidEndEditing(notification)
        field.controlTextDidEndEditing(notification)
        XCTAssertEqual(values, ["Writing"])
    }
}
