import XCTest
@testable import SpacesUltimate

@MainActor
final class LiveSpaceDetectionTests: XCTestCase {
    private let spaces = [DetectedSpace(stableID: "a", orderIndex: 1),
                          DetectedSpace(stableID: "b", orderIndex: 2)]

    func testMovedWindowsCannotOverrideLiveDesktopForAnyDisplayResolver() {
        // All visible windows moved to B, but preferences still assign them to A.
        let snapshot = SpaceDetectionResolver.DockSnapshot(spaces: spaces, currentStableID: "a",
                                                          spaceWindowIDs: ["a": [10, 20, 30]])
        let display = DisplaySpaceSnapshot(displayIdentifier: "Main", displayID: 1, screenName: "Screen",
                                           frame: nil, screenMatch: "main", spaces: spaces,
                                           currentStableID: "a", activeOrderIndex: 1, source: "saved preferences")
        let fallbacks = [
            SpaceDetectionResolver.displayResolution(display: display, snapshot: snapshot,
                                                      visibleWindowIDs: [10, 20, 30], fallbackOrderIndex: nil),
            SpaceDetectionResolver.mainDisplayResolution(display: display, snapshot: snapshot, visibleWindowIDs: [10]),
            SpaceDetectionResolver.builtInDisplayResolution(display: display, builtInIsMain: true,
                                                             snapshot: snapshot, visibleWindowIDs: [10, 20])
        ]
        for fallback in fallbacks {
            XCTAssertEqual(fallback.resolvedOrderIndex, 1)
            let result = SpaceDetectionResolver.applyingLiveSpace("b", spaces: spaces, to: fallback)
            XCTAssertEqual(result.resolvedOrderIndex, 2)
            XCTAssertEqual(result.confidence, .high)
            XCTAssertEqual(result.windowMatchedOrderIndex, 1, "Retain conflicting evidence for diagnosis")
        }
    }

    func testEmptyDesktopResolvesWithoutAnyWindowEvidence() {
        let fallback = emptyFallback()
        XCTAssertNil(fallback.resolvedOrderIndex)
        let result = SpaceDetectionResolver.applyingLiveSpace("b", spaces: spaces, to: fallback)
        XCTAssertEqual(result.resolvedOrderIndex, 2)
        XCTAssertEqual(result.visibleWindowIDCount, 0)
        XCTAssertNil(result.windowMatchedOrderIndex)
    }

    func testUnavailableLiveQueryLeavesExistingFallbackUnchanged() {
        let fallback = emptyFallback()
        XCTAssertEqual(SpaceDetectionResolver.applyingLiveSpace(nil, spaces: spaces, to: fallback), fallback)
    }

    func testUnknownLiveSpaceDoesNotClaimPreviousDesktop() {
        var fallback = emptyFallback()
        fallback.resolvedOrderIndex = 1
        let result = SpaceDetectionResolver.applyingLiveSpace("new-or-fullscreen-space", spaces: spaces, to: fallback)
        XCTAssertNil(result.resolvedOrderIndex)
        XCTAssertEqual(result.confidence, .fallback)
    }

    func testStableIdentityUsesExistingOrderRatherThanArrayPosition() {
        let reordered = [DetectedSpace(stableID: "a", orderIndex: 2), DetectedSpace(stableID: "b", orderIndex: 1)]
        XCTAssertEqual(SpaceDetectionResolver.applyingLiveSpace("b", spaces: reordered,
                                                                to: emptyFallback()).resolvedOrderIndex, 1)
    }

    func testLiveDisplaysMatchUUIDRatherThanArrayOrder() {
        let displays = [LiveSpaceReader.Display(identifier: "EXTERNAL", currentStableID: "b"),
                        LiveSpaceReader.Display(identifier: "BUILT-IN", currentStableID: "a")]
        XCTAssertEqual(LiveSpaceReader.currentStableID(for: "built-in", separateSpaces: true, in: displays), "a")
        XCTAssertEqual(LiveSpaceReader.currentStableID(for: "external", separateSpaces: true, in: displays), "b")
        XCTAssertNil(LiveSpaceReader.currentStableID(for: "new-display", separateSpaces: true, in: displays))
    }

    func testMainAliasIsOnlyAcceptedForSharedSpaces() {
        let displays = [LiveSpaceReader.Display(identifier: "Main", currentStableID: "b")]
        XCTAssertNil(LiveSpaceReader.currentStableID(for: "physical-uuid", separateSpaces: true, in: displays))
        XCTAssertEqual(LiveSpaceReader.currentStableID(for: "physical-uuid", separateSpaces: false, in: displays), "b")
    }

    func testAmbiguousDisplayRecordsAreNotTrusted() {
        let displays = [LiveSpaceReader.Display(identifier: "screen", currentStableID: "a"),
                        LiveSpaceReader.Display(identifier: "SCREEN", currentStableID: "b")]
        XCTAssertNil(LiveSpaceReader.currentStableID(for: "screen", separateSpaces: true, in: displays))
    }

    func testMalformedLiveDataFallsBackWithoutInventingIDs() {
        XCTAssertTrue(LiveSpaceReader.parse("unexpected format").isEmpty)
        let records: [[String: Any]] = [
            ["Display Identifier": "screen", "Current Space": ["uuid": "b"]],
            ["Display Identifier": "missing-current"],
            ["Display Identifier": "", "Current Space": ["uuid": "a"]],
            ["Display Identifier": "wrong-type", "Current Space": ["uuid": 42]],
            ["Display Identifier": "numeric-only", "Current Space": ["id64": 123]]
        ]
        XCTAssertEqual(LiveSpaceReader.parse(records), [.init(identifier: "screen", currentStableID: "b")])
    }

    private func emptyFallback() -> SpaceDisplayResolution {
        SpaceDetectionResolver.displayResolution(display: nil,
            snapshot: .init(spaces: spaces, currentStableID: "a", spaceWindowIDs: [:]),
            visibleWindowIDs: [], fallbackOrderIndex: nil)
    }
}
