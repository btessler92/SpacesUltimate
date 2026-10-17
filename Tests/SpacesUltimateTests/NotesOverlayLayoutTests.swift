import AppKit
import XCTest
@testable import SpacesUltimate

@MainActor
final class NotesOverlayLayoutTests: XCTestCase {
    func testSameNamesUseTwoRowsOnLaptopAndOneOnWideDisplay() {
        let spaces = namedSpaces(count: 16)
        let laptop = layout(spaces, screenWidth: 1728)
        let wide = layout(spaces, screenWidth: 2560)
        XCTAssertEqual(laptop.rowCount, 2)
        XCTAssertLessThan(laptop.minimumSingleRowNameFraction, 0.5)
        XCTAssertEqual(wide.rowCount, 1)
        XCTAssertGreaterThanOrEqual(wide.minimumSingleRowNameFraction, 0.5)
        XCTAssertGreaterThan(laptop.cardWidth, 150)
        XCTAssertGreaterThan(laptop.cardWidth, wide.cardWidth)
    }

    func testShortNamesDoNotExpandJustBecauseThereAreManyDesktops() {
        var spaces = namedSpaces(count: 16)
        for index in spaces.indices { spaces[index].name = "Lab" }
        XCTAssertEqual(layout(spaces, screenWidth: 1728).rowCount, 1)
        for index in spaces.indices { spaces[index].icon = "🔬" }
        XCTAssertEqual(layout(spaces, screenWidth: 1728).rowCount, 2)
    }

    func testFewDesktopsDoNotExpandWhenCardWidthIsNotDisplayConstrained() {
        var spaces = namedSpaces(count: 3)
        spaces[0].name = String(repeating: "Long desktop name ", count: 8)
        XCTAssertEqual(layout(spaces, screenWidth: 1728).rowCount, 1)
        XCTAssertEqual(layout([], screenWidth: 1728).rowCount, 1)
    }

    func testCompactRowsReduceHeightWithoutMovingTheTopEdge() {
        let spaces = namedSpaces(count: 16)
        let laptop = layout(spaces, screenWidth: 1728)
        let wide = layout(spaces, screenWidth: 2560)
        let screen = NSRect(x: -1728, y: -200, width: 1728, height: 1000)
        let twoRows = laptop.panelFrame(visibleFrame: screen, width: 1696, baseHeight: 64)
        let oneRow = wide.panelFrame(visibleFrame: screen, width: 1696, baseHeight: 64)
        XCTAssertEqual(oneRow.height, 64)
        XCTAssertEqual(twoRows.height, 104)
        XCTAssertLessThan(twoRows.height, oneRow.height * 2)
        XCTAssertEqual(twoRows.maxY, oneRow.maxY)
        XCTAssertTrue(screen.contains(twoRows))
        let clamped = laptop.panelFrame(visibleFrame: screen, width: 1696, baseHeight: 1000)
        XCTAssertTrue(screen.contains(clamped))
        let minimum = laptop.panelFrame(visibleFrame: screen, width: 1696, baseHeight: AppSettings.minimumNotesOverlayHeightPixels)
        XCTAssertEqual(minimum.height, 100)
    }

    func testOddAndEvenCountsStaggerEveryCardWithoutOverlapAndKeepActionsAligned() {
        _ = NSApplication.shared
        for count in [15, 16] {
            let spaces = namedSpaces(count: count)
            let arrangement = layout(spaces, screenWidth: 1728)
            XCTAssertEqual(arrangement.rowCount, 2)
            let frame = arrangement.panelFrame(visibleFrame: NSRect(x: -1728, y: 0, width: 1728, height: 1000),
                                               width: 1696, baseHeight: 64)
            let panel = NSPanel(contentRect: frame,
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            var selected: Int?
            let view = LabelOverlayView(spaces: spaces, activeIndex: 1, itemOpacity: 0.34,
                screenFrame: NSRect(origin: .zero, size: frame.size), presentationLayout: arrangement,
                beginEditing: {}, rename: { _ in }, navigate: { selected = $0.orderIndex }, close: {})
            panel.contentView = view
            let cards = view.cardScreenFrames
            XCTAssertEqual(cards.count, count)
            XCTAssertTrue(cards.allSatisfy { panel.frame.contains($0) && $0.height > 30 })
            XCTAssertEqual(Set(cards.map { Int($0.maxY) }).count, 2)
            for first in cards.indices {
                for second in cards.indices where second > first {
                    XCTAssertFalse(cards[first].intersects(cards[second]))
                }
            }
            let buttons = descendants(view).compactMap { $0 as? NSButton }.filter { $0.tag > 0 }
                .sorted { $0.tag < $1.tag }
            var centers: [NSPoint] = []
            for button in buttons {
                let frame = panel.convertToScreen(button.convert(button.bounds, to: nil))
                let center = NSPoint(x: frame.midX, y: frame.midY)
                centers.append(center)
                XCTAssertEqual(frame.width, 24)
                XCTAssertEqual(frame.height, 24)
                XCTAssertTrue(panel.frame.contains(frame))
                let card = cards.first { $0.contains(frame) }
                XCTAssertNotNil(card, "Each square Go button must be fully inside its own card")
                XCTAssertEqual((card?.maxX ?? 0) - frame.maxX, 6, accuracy: 0.1)
                XCTAssertEqual(card?.midY ?? 0, frame.midY, accuracy: 0.1)
                XCTAssertTrue(view.containsCardOrNavigationButton(at: center))
                XCTAssertEqual(view.navigationTarget(at: center)?.space.orderIndex, button.tag)
                XCTAssertFalse(view.isCloseButton(at: center))
                let gap = NSPoint(x: (card?.maxX ?? frame.maxX) + 5, y: frame.midY)
                XCTAssertFalse(view.containsCardOrNavigationButton(at: gap))
                button.performClick(nil)
                XCTAssertEqual(selected, button.tag)
            }
            XCTAssertGreaterThan(centers[0].y, centers[1].y)
            XCTAssertLessThan(centers[0].x, centers[1].x)
            XCTAssertLessThan(centers[1].x, centers[2].x)
            for title in descendants(view).compactMap({ $0 as? InlineEditableNameField }) {
                let frame = panel.convertToScreen(title.convert(title.bounds, to: nil))
                XCTAssertNil(view.navigationTarget(at: NSPoint(x: frame.midX, y: frame.midY)))
                XCTAssertTrue(view.containsCardOrNavigationButton(at: NSPoint(x: frame.midX, y: frame.midY)))
            }
            panel.close()
        }
    }

    func testCompactCardsKeepNamesNumbersAndNotesVisibleAtMinimumHeight() {
        _ = NSApplication.shared
        for screenWidth: CGFloat in [1280, 1728, 2560] {
            var spaces = namedSpaces(count: 16)
            for index in spaces.indices {
                spaces[index].name = "A longer Desktop name"
                spaces[index].note = "A note that should remain readable below the name."
            }
            let arrangement = layout(spaces, screenWidth: screenWidth)
            XCTAssertEqual(arrangement.rowCount, 2)
            let width = NotesOverlayLayout.panelWidth(visibleWidth: screenWidth, spaceCount: spaces.count)
            let frame = arrangement.panelFrame(visibleFrame: NSRect(x: 0, y: 0, width: screenWidth, height: 1000),
                width: width, baseHeight: AppSettings.minimumNotesOverlayHeightPixels)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            let view = LabelOverlayView(spaces: spaces, activeIndex: 1, itemOpacity: 0.34,
                screenFrame: NSRect(origin: .zero, size: frame.size), presentationLayout: arrangement,
                beginEditing: {}, rename: { _ in }, close: {})
            panel.contentView = view
            view.layoutSubtreeIfNeeded()
            let textFields = descendants(view).compactMap { $0 as? NSTextField }
            XCTAssertEqual(textFields.count, spaces.count * 3)
            for field in textFields {
                let screenFrame = panel.convertToScreen(field.convert(field.bounds, to: nil))
                XCTAssertTrue(view.cardScreenFrames.contains { $0.insetBy(dx: -0.5, dy: -0.5).contains(screenFrame) },
                              "Text must fit vertically in its own compact card: \(field.stringValue)")
                XCTAssertGreaterThanOrEqual(field.visibleRect.height, field.bounds.height - 0.5)
            }
            panel.close()
        }
    }

    private func namedSpaces(count: Int) -> [SpaceMetadata] {
        var spaces = SpaceConfig.defaults(spaceCount: count).spaces
        for index in spaces.indices { spaces[index].name = "MouseTracker" }
        return spaces
    }

    private func layout(_ spaces: [SpaceMetadata], screenWidth: CGFloat) -> NotesOverlayLayout {
        NotesOverlayLayout(spaces: spaces, availableWidth: NotesOverlayLayout.panelWidth(
            visibleWidth: screenWidth, spaceCount: spaces.count))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        // Native buttons can contain private text fields used to draw their title.
        // Inspect the app's controls, without counting those implementation details.
        view.subviews.flatMap { [$0] + ($0 is NSButton ? [] : descendants($0)) }
    }
}
