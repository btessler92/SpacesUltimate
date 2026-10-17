import AppKit
import XCTest
@testable import SpacesUltimate

final class NotesOverlayPresentationTests: XCTestCase {
    func testOutsideActionsKeepNotesVisibleUntilMissionControlExits() {
        var state = NotesOverlayInteractionState()
        state.show(followsMissionControl: true)
        // Repeated clicks and drags on native Mission Control controls must not dismiss notes.
        for _ in 0..<3 {
            XCTAssertFalse(state.shouldDismissForOutsideClick(missionControlIsActive: true))
            XCTAssertTrue(state.shouldDismissOnMissionControlExit)
        }
    }

    func testOutsideActionAfterEditingWaitsForExitAndAnotherCardClickCanRetainAgain() {
        var state = NotesOverlayInteractionState()
        state.show(followsMissionControl: true)
        state.interactWithCard()
        XCTAssertFalse(state.shouldDismissForOutsideClick(missionControlIsActive: true))
        XCTAssertTrue(state.shouldDismissOnMissionControlExit)
        state.interactWithCard()
        XCTAssertFalse(state.shouldDismissOnMissionControlExit)
        XCTAssertTrue(state.keepsOpenAfterMissionControl)
    }

    func testOutsideClickStillDismissesManualOrRetainedNotesAfterMissionControl() {
        for automatic in [false, true] {
            var state = NotesOverlayInteractionState()
            state.show(followsMissionControl: automatic)
            state.interactWithCard()
            XCTAssertTrue(state.shouldDismissForOutsideClick(missionControlIsActive: false))
            state.hide()
            XCTAssertFalse(state.shouldDismissForOutsideClick(missionControlIsActive: true))
            XCTAssertFalse(state.shouldDismissOnMissionControlExit)
        }
    }

    func testCardClickKeepsNotesOpenWhenMissionControlExits() {
        var state = NotesOverlayInteractionState()
        state.show(followsMissionControl: true)
        XCTAssertTrue(state.shouldDismissOnMissionControlExit)

        state.interactWithCard()
        XCTAssertFalse(state.shouldDismissOnMissionControlExit)
        XCTAssertTrue(state.keepsOpenAfterMissionControl)

        // The second click of a double-click must also preserve the card for editing.
        state.interactWithCard()
        XCTAssertFalse(state.shouldDismissOnMissionControlExit)
    }

    func testOutsideDismissalClearsCardRetentionForTheNextSession() {
        var state = NotesOverlayInteractionState()
        state.show(followsMissionControl: true)
        state.interactWithCard()
        state.hide()
        XCTAssertFalse(state.keepsOpenAfterMissionControl)

        state.show(followsMissionControl: true)
        XCTAssertTrue(state.shouldDismissOnMissionControlExit)
        XCTAssertFalse(state.keepsOpenAfterMissionControl)
    }

    func testManualNotesStayOpenOnMissionControlExit() {
        var state = NotesOverlayInteractionState()
        state.show(followsMissionControl: false)
        XCTAssertFalse(state.shouldDismissOnMissionControlExit)
    }

    @MainActor
    func testOnlyVisibleCardsAreProtectedFromOutsideClickDismissal() {
        _ = NSApplication.shared
        let panel = KeyableOverlayPanel(
            contentRect: NSRect(x: -1000, y: 300, width: 800, height: 64),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        let view = LabelOverlayView(
            spaces: SpaceConfig.defaults(spaceCount: 3).spaces,
            activeIndex: 1, itemOpacity: 0.34,
            screenFrame: NSRect(x: 0, y: 0, width: 800, height: 64),
            beginEditing: {}, rename: { _ in }, close: {}
        )
        panel.contentView = view
        let cards = view.cardScreenFrames.sorted { $0.minX < $1.minX }
        XCTAssertEqual(cards.count, 3)
        guard cards.count == 3 else { return }
        XCTAssertTrue(cards.allSatisfy { panel.frame.contains($0) })
        let gap = NSPoint(x: (cards[0].maxX + cards[1].minX) / 2, y: cards[0].midY)
        XCTAssertFalse(cards.contains { $0.contains(gap) })
        let closeArea = NSPoint(x: panel.frame.maxX - 24, y: panel.frame.maxY - 16)
        XCTAssertFalse(cards.contains { $0.contains(closeArea) })
        XCTAssertTrue(view.isCloseButton(at: closeArea))
        XCTAssertFalse(view.isCloseButton(at: gap))
        XCTAssertTrue(cards.contains { $0.contains(NSPoint(x: cards[0].midX, y: cards[0].midY)) })
        panel.close()
    }

    @MainActor
    func testGoButtonRoutesToItsOwnSpaceAndStaysInsideCardHitArea() {
        _ = NSApplication.shared
        let panel = KeyableOverlayPanel(
            contentRect: NSRect(x: -1000, y: 300, width: 800, height: 64),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        var selected: Int?
        let view = LabelOverlayView(
            spaces: SpaceConfig.defaults(spaceCount: 3).spaces,
            activeIndex: 1, itemOpacity: 0.34,
            screenFrame: NSRect(x: 0, y: 0, width: 800, height: 64),
            beginEditing: {}, rename: { _ in }, navigate: { selected = $0.orderIndex }, close: {}
        )
        panel.contentView = view
        view.layoutSubtreeIfNeeded()
        func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        let buttons = descendants(of: view).compactMap { $0 as? NSButton }.filter { $0.tag > 0 }
        XCTAssertEqual(buttons.count, 3)
        for button in buttons {
            let frame = panel.convertToScreen(button.convert(button.bounds, to: nil))
            let center = NSPoint(x: frame.midX, y: frame.midY)
            XCTAssertTrue(view.cardScreenFrames.contains { $0.contains(center) })
            XCTAssertEqual(view.navigationTarget(at: center)?.space.orderIndex, button.tag)
            button.performClick(nil)
            XCTAssertEqual(selected, button.tag)
        }
        for title in descendants(of: view).compactMap({ $0 as? InlineEditableNameField }) {
            let frame = panel.convertToScreen(title.convert(title.bounds, to: nil))
            XCTAssertNil(view.navigationTarget(at: NSPoint(x: frame.midX, y: frame.midY)))
        }
    }

    func testHighlightKeepsCurrentDesktopWhileDetectionIsTemporarilyUnresolved() {
        var policy = NotesOverlayHighlightPolicy()
        XCTAssertEqual(
            policy.nextActiveIndex(current: 6, resolved: nil),
            6
        )
    }

    func testHighlightMovesAfterDesktopDetectionIsConfirmed() {
        var policy = NotesOverlayHighlightPolicy()
        XCTAssertEqual(
            policy.nextActiveIndex(current: 4, resolved: 5),
            4
        )
        XCTAssertEqual(
            policy.nextActiveIndex(current: 4, resolved: 5),
            5
        )
    }

    func testHighlightIgnoresSingleSnapshotReversion() {
        var policy = NotesOverlayHighlightPolicy()
        XCTAssertEqual(policy.nextActiveIndex(current: 5, resolved: 4), 5)
        XCTAssertEqual(policy.nextActiveIndex(current: 5, resolved: 5), 5)
        XCTAssertEqual(policy.nextActiveIndex(current: 5, resolved: 4), 5)
    }

    func testFingerprintIgnoresActiveDesktopOnlyChanges() {
        let original = SpaceConfig.defaults(spaceCount: 3)
        var activeDesktopChanged = original
        activeDesktopChanged.lastKnownActiveOrderIndex = 2

        XCTAssertEqual(
            NotesOverlayPresentationFingerprint(config: original),
            NotesOverlayPresentationFingerprint(config: activeDesktopChanged)
        )
    }

    func testFingerprintChangesForVisibleOverlayContentAndSizing() {
        let original = SpaceConfig.defaults(spaceCount: 3)

        var renamed = original
        renamed.spaces[0].name = "Renamed"
        XCTAssertNotEqual(
            NotesOverlayPresentationFingerprint(config: original),
            NotesOverlayPresentationFingerprint(config: renamed)
        )

        var resized = original
        resized.settings.notesOverlayHeightPixels += 10
        XCTAssertNotEqual(
            NotesOverlayPresentationFingerprint(config: original),
            NotesOverlayPresentationFingerprint(config: resized)
        )

        var opacityChanged = original
        opacityChanged.settings.notesOverlayItemOpacity += 0.1
        XCTAssertNotEqual(
            NotesOverlayPresentationFingerprint(config: original),
            NotesOverlayPresentationFingerprint(config: opacityChanged)
        )
        var backgroundChanged = original
        backgroundChanged.settings.notesOverlayBackgroundOpacity = 0
        XCTAssertNotEqual(NotesOverlayPresentationFingerprint(config: original),
                          NotesOverlayPresentationFingerprint(config: backgroundChanged))
    }

    @MainActor
    func testLiveOpacityChangesPreserveTextCardsAndActionFrames() throws {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 64),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let view = LabelOverlayView(spaces: SpaceConfig.defaults(spaceCount: 3).spaces,
            activeIndex: 1, itemOpacity: 0.34, backgroundOpacity: 0.58,
            screenFrame: NSRect(x: 0, y: 0, width: 800, height: 64),
            beginEditing: {}, rename: { _ in }, close: {})
        panel.contentView = view
        let frames = view.cardScreenFrames
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let titles = descendants(view).compactMap { $0 as? InlineEditableNameField }
        let background = try XCTUnwrap(descendants(view).compactMap { $0 as? NSVisualEffectView }.first)
        let cards = descendants(view).filter { $0.layer?.cornerRadius == 12 }
        XCTAssertEqual(cards.count, 3)
        view.updateOpacity(item: 0.73, background: 0)
        XCTAssertEqual(background.alphaValue, 0)
        XCTAssertTrue(cards.allSatisfy { abs(($0.layer?.backgroundColor?.alpha ?? 0) - 0.73) < 0.001 })
        XCTAssertTrue(titles.allSatisfy { $0.alphaValue == 1 })
        XCTAssertEqual(view.cardScreenFrames, frames)
        view.updateOpacity(item: 0.73, background: 1)
        XCTAssertEqual(background.alphaValue, 1)
        XCTAssertTrue(cards.allSatisfy { abs(($0.layer?.backgroundColor?.alpha ?? 0) - 0.73) < 0.001 })
        XCTAssertEqual(view.cardScreenFrames, frames)
    }
}
