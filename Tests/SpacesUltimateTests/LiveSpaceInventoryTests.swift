import AppKit
import XCTest
@testable import SpacesUltimate

@MainActor
final class LiveSpaceInventoryTests: XCTestCase {
    func testFullscreenDoesNotConsumeDesktopNumberAndMovedDesktopStaysOnLiveDisplay() throws {
        let inventory = try XCTUnwrap(LiveSpaceInventory(displays: displays()))
        XCTAssertEqual(inventory.desktops.map(\.orderIndex), Array(1...17))
        XCTAssertEqual(inventory.desktops[14].stableID, "moved-from-old-monitor")
        XCTAssertEqual(inventory.desktops.last?.stableID, "secondary-desktop")
        XCTAssertEqual(inventory.fullscreenCards.count, 1)
        XCTAssertEqual(inventory.fullscreenCards.first?.name, "Windows App")
        var saved = SpaceConfig.defaults(spaceCount: 17).spaces
        for index in saved.indices { saved[index].stableID = inventory.desktops[index].stableID }
        let mainCards = inventory.cards(for: inventory.displays[0], savedSpaces: saved)
        XCTAssertEqual(mainCards.count, 17)
        XCTAssertTrue(mainCards[4].isFullscreen)
        XCTAssertEqual(mainCards[5].orderIndex, 5)
        XCTAssertEqual(mainCards[15].stableID, "moved-from-old-monitor")
        XCTAssertEqual(inventory.cards(for: inventory.displays[1], savedSpaces: saved).map(\.orderIndex), [17])
    }

    func testNavigationCountsFullscreenStepsInBothDirectionsAndOnSecondDisplay() throws {
        var records = displays()
        records[0].currentStableID = "desktop-4"
        let inventory = try XCTUnwrap(LiveSpaceInventory(displays: records))
        XCTAssertEqual(inventory.relativeOffset(to: "desktop-5"), 2)
        XCTAssertEqual(inventory.relativeOffset(to: "fullscreen"), 1)
        XCTAssertEqual(inventory.relativeOffset(to: "secondary-desktop"), 0)
        XCTAssertNil(inventory.relativeOffset(to: "removed"))
        records[0].currentStableID = "fullscreen"
        let fromFullscreen = try XCTUnwrap(LiveSpaceInventory(displays: records))
        XCTAssertEqual(fromFullscreen.relativeOffset(to: "desktop-4"), -1)
        XCTAssertEqual(fromFullscreen.relativeOffset(to: "desktop-5"), 1)
        XCTAssertEqual(fromFullscreen.relativeOffset(to: "fullscreen"), 0)
    }

    func testMalformedOrIncompleteInventoriesAreRejectedAsAWhole() {
        var records = displays()
        records[1].spaces = nil
        XCTAssertNil(LiveSpaceInventory(displays: records))
        records = displays()
        records[1].identifier = "MAIN"
        XCTAssertNil(LiveSpaceInventory(displays: records))
        records = displays()
        let duplicate = records[0].spaces![0]
        records[1].spaces?.append(duplicate)
        XCTAssertNil(LiveSpaceInventory(displays: records))
        records = displays()
        records[0].currentStableID = "missing"
        XCTAssertNil(LiveSpaceInventory(displays: records))
        records = displays()
        records[0].spaces?[0].type = 99
        XCTAssertNil(LiveSpaceInventory(displays: records))
    }

    func testParserUsesAppNamesFromFullscreenTilesWithoutWindowTitles() throws {
        let records: [[String: Any]] = [[
            "Display Identifier": "screen", "Current Space": ["uuid": "desktop"],
            "Spaces": [
                ["uuid": "desktop", "type": 0],
                ["uuid": "fullscreen", "type": 4, "TileLayoutManager": ["TileSpaces": [
                    ["appName": "Windows App", "name": "Private window title"],
                    ["appName": "Notes"], ["appName": "Windows App"]
                ]]]
            ]
        ]]
        let parsed = LiveSpaceReader.parse(records)
        let inventory = try XCTUnwrap(LiveSpaceInventory(displays: parsed))
        XCTAssertEqual(inventory.fullscreenCards[0].name, "Windows App + Notes")
        XCTAssertEqual(MenuBarStatusContent.badgeText(for: inventory.fullscreenCards[0]), "⛶")
        XCTAssertEqual(inventory.fullscreenCards[0].desktopLabel, "Fullscreen app")
    }

    func testParserDoesNotSilentlyDropUnrecognizedSpacesAndRenumberDesktops() {
        let records: [[String: Any]] = [[
            "Display Identifier": "screen", "Current Space": ["uuid": "desktop"],
            "Spaces": [["uuid": "desktop", "type": 0], ["uuid": "unknown", "type": 99]]
        ]]
        XCTAssertNil(LiveSpaceInventory(displays: LiveSpaceReader.parse(records)))
    }

    func testFullscreenResolutionClearsStaleDesktopAndRegularResolutionClearsFullscreen() throws {
        let inventory = try XCTUnwrap(LiveSpaceInventory(displays: displays()))
        let fallback = SpaceDetectionResolver.displayResolution(display: nil,
            snapshot: .init(spaces: inventory.desktops, currentStableID: "desktop-4", spaceWindowIDs: [:]),
            visibleWindowIDs: [], fallbackOrderIndex: 4)
        let fullscreen = SpaceDetectionResolver.applyingLiveSpace("fullscreen", spaces: inventory.desktops,
            to: fallback, fullscreenSpace: inventory.fullscreenCards[0])
        XCTAssertNil(fullscreen.resolvedOrderIndex)
        XCTAssertEqual(fullscreen.fullscreenSpace?.name, "Windows App")
        XCTAssertEqual(fullscreen.confidence, .high)
        let regular = SpaceDetectionResolver.applyingLiveSpace("desktop-5", spaces: inventory.desktops, to: fullscreen)
        XCTAssertEqual(regular.resolvedOrderIndex, 5)
        XCTAssertNil(regular.fullscreenSpace)
    }

    func testFullscreenHighlightCanMoveFromAndBackToDesktop() {
        var policy = NotesOverlayHighlightPolicy()
        XCTAssertEqual(policy.nextActiveIndex(current: 4, resolved: -1), 4)
        XCTAssertEqual(policy.nextActiveIndex(current: 4, resolved: -1), -1)
        XCTAssertEqual(policy.nextActiveIndex(current: -1, resolved: 5), -1)
        XCTAssertEqual(policy.nextActiveIndex(current: -1, resolved: 5), 5)
    }

    func testFullscreenCardIsUnnumberedReadOnlyAndHasItsOwnNavigationTarget() throws {
        _ = NSApplication.shared
        let inventory = try XCTUnwrap(LiveSpaceInventory(displays: displays()))
        let card = inventory.fullscreenCards[0]
        let layout = NotesOverlayLayout(spaces: [card], availableWidth: 800)
        var target: String?
        let view = LabelOverlayView(spaces: [card], activeIndex: card.orderIndex, itemOpacity: 0.34,
            screenFrame: NSRect(x: 0, y: 0, width: 800, height: 64), presentationLayout: layout,
            beginEditing: {}, rename: { _ in XCTFail("Fullscreen app names are read-only") },
            navigate: { target = $0.stableID }, close: {})
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let children = descendants(view)
        let title = try XCTUnwrap(children.compactMap { $0 as? InlineEditableNameField }.first)
        XCTAssertEqual(title.stringValue, "Windows App")
        XCTAssertFalse(title.allowsNameEditing)
        XCTAssertTrue(children.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "⛶" })
        XCTAssertFalse(children.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "-1" })
        let go = try XCTUnwrap(children.compactMap { $0 as? NSButton }.first { $0.tag == card.orderIndex })
        go.performClick(nil)
        XCTAssertEqual(target, "fullscreen")
    }

    private func displays() -> [LiveSpaceReader.Display] {
        var main = (1...16).map { LiveSpaceReader.ManagedSpace(stableID: "desktop-\($0)", type: 0) }
        main[14].stableID = "moved-from-old-monitor"
        main.insert(.init(stableID: "fullscreen", type: 4, appName: "Windows App"), at: 4)
        return [.init(identifier: "main", currentStableID: "desktop-14", spaces: main),
                .init(identifier: "secondary", currentStableID: "secondary-desktop",
                      spaces: [.init(stableID: "secondary-desktop", type: 0)])]
    }
}
