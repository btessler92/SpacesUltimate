import XCTest
@testable import SpacesUltimate

final class SpaceDetectionResolverTests: XCTestCase {
    func testDockCurrentStableIDResolvesOrderIndex() {
        let snapshot = snapshot(currentStableID: "space-b")

        XCTAssertEqual(SpaceDetectionResolver.activeOrderIndex(from: snapshot), 2)
    }

    func testUnknownDockCurrentStableIDDoesNotResolve() {
        let snapshot = snapshot(currentStableID: "space-z")

        XCTAssertNil(SpaceDetectionResolver.activeOrderIndex(from: snapshot))
    }

    func testVisibleUniqueWindowIDsResolveBestSpace() {
        let snapshot = snapshot(spaceWindowIDs: [
            "space-a": [10],
            "space-b": [20, 21],
            "space-c": [30]
        ])

        XCTAssertEqual(
            SpaceDetectionResolver.activeOrderIndexFromVisibleWindows(in: snapshot, visibleWindowIDs: [20, 21, 30]),
            2
        )
    }

    func testVisibleWindowMatchReportsCandidatesAndIgnoredSharedWindows() {
        let snapshot = snapshot(spaceWindowIDs: [
            "space-a": [10, 99],
            "space-b": [20, 21, 99],
            "space-c": [30]
        ])

        let result = SpaceDetectionResolver.visibleWindowMatch(
            in: snapshot,
            visibleWindowIDs: [20, 21, 30, 99, 777]
        )

        XCTAssertEqual(result.orderIndex, 2)
        XCTAssertEqual(result.uniqueVisibleWindowIDCount, 3)
        XCTAssertEqual(result.ignoredSharedVisibleWindowIDCount, 1)
        XCTAssertEqual(result.candidates.map(\.orderIndex), [2, 3])
        XCTAssertEqual(result.candidates.first?.matchedVisibleWindowCount, 2)
        XCTAssertEqual(result.candidates.first?.knownWindowCount, 3)
    }

    func testWindowIDsSharedAcrossSpacesAreIgnored() {
        let snapshot = snapshot(spaceWindowIDs: [
            "space-a": [10, 99],
            "space-b": [20, 99],
            "space-c": [30, 99]
        ])

        XCTAssertNil(
            SpaceDetectionResolver.activeOrderIndexFromVisibleWindows(in: snapshot, visibleWindowIDs: [99])
        )

        let result = SpaceDetectionResolver.visibleWindowMatch(in: snapshot, visibleWindowIDs: [99])
        XCTAssertNil(result.orderIndex)
        XCTAssertEqual(result.uniqueVisibleWindowIDCount, 0)
        XCTAssertEqual(result.ignoredSharedVisibleWindowIDCount, 1)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testTiedVisibleWindowMatchesDoNotResolve() {
        let snapshot = snapshot(spaceWindowIDs: [
            "space-a": [10],
            "space-b": [20],
            "space-c": [30, 31]
        ])

        XCTAssertNil(
            SpaceDetectionResolver.activeOrderIndexFromVisibleWindows(in: snapshot, visibleWindowIDs: [10, 20])
        )

        let result = SpaceDetectionResolver.visibleWindowMatch(in: snapshot, visibleWindowIDs: [10, 20])
        XCTAssertNil(result.orderIndex)
        XCTAssertEqual(result.candidates.map(\.orderIndex), [1, 2])
    }

    func testUnknownSpaceWindowIDsDoNotResolve() {
        let snapshot = snapshot(spaceWindowIDs: [
            "missing-space": [10, 11]
        ])

        XCTAssertNil(
            SpaceDetectionResolver.activeOrderIndexFromVisibleWindows(in: snapshot, visibleWindowIDs: [10, 11])
        )
    }

    func testDetectionSourcePriority() {
        XCTAssertEqual(
            SpaceDetectionResolver.detectionSource(
                hasDetectedSpaces: true,
                hasDockActiveSpace: true,
                hasWindowMatchedActiveSpace: true
            ),
            "Dock preferences Current Space UUID"
        )
        XCTAssertEqual(
            SpaceDetectionResolver.detectionSource(
                hasDetectedSpaces: true,
                hasDockActiveSpace: true,
                hasWindowMatchedActiveSpace: false
            ),
            "Dock preferences Current Space UUID"
        )
        XCTAssertEqual(
            SpaceDetectionResolver.detectionSource(
                hasDetectedSpaces: true,
                hasDockActiveSpace: false,
                hasWindowMatchedActiveSpace: false
            ),
            "Dock preferences + CGWindow heuristic"
        )
        XCTAssertEqual(
            SpaceDetectionResolver.detectionSource(
                hasDetectedSpaces: false,
                hasDockActiveSpace: false,
                hasWindowMatchedActiveSpace: false
            ),
            "manual/order fallback"
        )
    }

    func testDisplayResolutionPrefersDockCurrentWhenWindowMatchDisagrees() {
        let dockDisplay = displaySnapshot(activeOrderIndex: 1, currentStableID: "space-a")
        let snapshot = snapshot(
            currentStableID: "space-a",
            spaceWindowIDs: [
                "space-a": [10],
                "space-b": [20, 21]
            ]
        )

        let result = SpaceDetectionResolver.displayResolution(
            display: dockDisplay,
            snapshot: snapshot,
            visibleWindowIDs: [20, 21],
            fallbackOrderIndex: 3
        )

        XCTAssertEqual(result.resolvedOrderIndex, 1)
        XCTAssertEqual(result.windowMatchedOrderIndex, 2)
        XCTAssertEqual(result.dockResolvedOrderIndex, 1)
        XCTAssertEqual(result.source, "Dock monitor Current Space UUID (visible-window conflict)")
        XCTAssertEqual(result.confidence, .medium)
    }

    func testDisplayResolutionUsesVisibleWindowMatchWhenDockCurrentIsUnavailable() {
        let dockDisplay = displaySnapshot(activeOrderIndex: nil, currentStableID: nil)
        let snapshot = snapshot(spaceWindowIDs: [
            "space-a": [10],
            "space-b": [20, 21]
        ])

        let result = SpaceDetectionResolver.displayResolution(
            display: dockDisplay,
            snapshot: snapshot,
            visibleWindowIDs: [20, 21],
            fallbackOrderIndex: 3
        )

        XCTAssertEqual(result.resolvedOrderIndex, 2)
        XCTAssertEqual(result.windowMatchedOrderIndex, 2)
        XCTAssertNil(result.dockResolvedOrderIndex)
        XCTAssertEqual(result.source, "screen visible-window Space match")
        XCTAssertEqual(result.confidence, .medium)
    }

    func testDisplayResolutionDoesNotTrustMainAliasWhenVisibleWindowMatchExists() {
        let dockDisplay = displaySnapshot(activeOrderIndex: 1, currentStableID: "space-a", screenMatch: "main")
        let snapshot = snapshot(
            currentStableID: "space-a",
            spaceWindowIDs: [
                "space-a": [10],
                "space-b": [20, 21]
            ]
        )

        let result = SpaceDetectionResolver.displayResolution(
            display: dockDisplay,
            snapshot: snapshot,
            visibleWindowIDs: [20, 21],
            fallbackOrderIndex: nil
        )

        XCTAssertEqual(result.resolvedOrderIndex, 2)
        XCTAssertEqual(result.dockResolvedOrderIndex, 1)
        XCTAssertEqual(result.windowMatchedOrderIndex, 2)
        XCTAssertEqual(result.source, "screen visible-window Space match (untrusted Dock monitor match)")
        XCTAssertEqual(result.confidence, .medium)
    }

    func testDisplayResolutionFallsBackToDockCurrentWhenWindowMatchIsAmbiguous() {
        let dockDisplay = displaySnapshot(activeOrderIndex: 1, currentStableID: "space-a")
        let snapshot = snapshot(spaceWindowIDs: [
            "space-a": [10],
            "space-b": [20]
        ])

        let result = SpaceDetectionResolver.displayResolution(
            display: dockDisplay,
            snapshot: snapshot,
            visibleWindowIDs: [10, 20],
            fallbackOrderIndex: 3
        )

        XCTAssertEqual(result.resolvedOrderIndex, 1)
        XCTAssertNil(result.windowMatchedOrderIndex)
        XCTAssertEqual(result.source, "Dock monitor Current Space UUID")
        XCTAssertEqual(result.confidence, .high)
    }

    func testDisplayResolutionFallsBackToGlobalActiveWhenDisplayIsCollapsedOrUnmatched() {
        let snapshot = snapshot(spaceWindowIDs: [
            "space-a": [10]
        ])

        let result = SpaceDetectionResolver.displayResolution(
            display: nil,
            snapshot: snapshot,
            visibleWindowIDs: [],
            fallbackOrderIndex: 3
        )

        XCTAssertEqual(result.resolvedOrderIndex, 3)
        XCTAssertEqual(result.source, "global active Space fallback")
        XCTAssertEqual(result.confidence, .fallback)
        XCTAssertEqual(result.screenMatch, "unmatched")
    }

    func testBuiltInDisplayResolutionTrustsExactDisplayUUID() {
        let dockDisplay = displaySnapshot(activeOrderIndex: 1, currentStableID: "space-a")
        let snapshot = snapshot(
            currentStableID: "space-a",
            spaceWindowIDs: [
                "space-a": [10],
                "space-b": [20, 21]
            ]
        )

        let result = SpaceDetectionResolver.builtInDisplayResolution(
            display: dockDisplay,
            builtInIsMain: true,
            snapshot: snapshot,
            visibleWindowIDs: [10]
        )

        XCTAssertEqual(result.resolvedOrderIndex, 1)
        XCTAssertEqual(result.source, "built-in Dock Current Space UUID")
        XCTAssertEqual(result.confidence, .high)
    }

    func testBuiltInDisplayResolutionUsesVisibleWindowsWhenMainAliasConflicts() {
        let dockDisplay = displaySnapshot(activeOrderIndex: 1, currentStableID: "space-a", screenMatch: "main")
        let snapshot = snapshot(
            currentStableID: "space-a",
            spaceWindowIDs: [
                "space-a": [10],
                "space-b": [20, 21]
            ]
        )

        let result = SpaceDetectionResolver.builtInDisplayResolution(
            display: dockDisplay,
            builtInIsMain: true,
            snapshot: snapshot,
            visibleWindowIDs: [20, 21]
        )

        XCTAssertEqual(result.resolvedOrderIndex, 2)
        XCTAssertEqual(result.dockResolvedOrderIndex, 1)
        XCTAssertEqual(result.windowMatchedOrderIndex, 2)
        XCTAssertEqual(result.source, "built-in visible-window Space match (stale Dock Main conflict)")
        XCTAssertEqual(result.confidence, .medium)
    }

    func testBuiltInDisplayResolutionTrustsMainAliasWhenItAgreesWithVisibleWindows() {
        let dockDisplay = displaySnapshot(activeOrderIndex: 2, currentStableID: "space-b", screenMatch: "main")
        let snapshot = snapshot(
            currentStableID: "space-b",
            spaceWindowIDs: [
                "space-a": [10],
                "space-b": [20, 21]
            ]
        )

        let result = SpaceDetectionResolver.builtInDisplayResolution(
            display: dockDisplay,
            builtInIsMain: true,
            snapshot: snapshot,
            visibleWindowIDs: [20, 21]
        )

        XCTAssertEqual(result.resolvedOrderIndex, 2)
        XCTAssertEqual(result.source, "built-in Dock Main Current Space UUID")
        XCTAssertEqual(result.confidence, .medium)
    }

    func testBuiltInDisplayResolutionReturnsUnknownWithoutTrustedEvidence() {
        let dockDisplay = displaySnapshot(activeOrderIndex: 1, currentStableID: "space-a", screenMatch: "index-fallback")
        let snapshot = snapshot(currentStableID: "space-a")

        let result = SpaceDetectionResolver.builtInDisplayResolution(
            display: dockDisplay,
            builtInIsMain: true,
            snapshot: snapshot,
            visibleWindowIDs: []
        )

        XCTAssertNil(result.resolvedOrderIndex)
        XCTAssertEqual(result.dockResolvedOrderIndex, 1)
        XCTAssertEqual(result.source, "built-in display unresolved")
        XCTAssertEqual(result.confidence, .fallback)
    }

    func testNotesOverlayUsesAllSpacesWhenResolvedActiveSpaceIsMissingFromMonitorList() {
        let display = displaySnapshot(
            activeOrderIndex: 1,
            currentStableID: "space-a",
            spaces: [
                DetectedSpace(stableID: "space-a", orderIndex: 1),
                DetectedSpace(stableID: "space-b", orderIndex: 2)
            ]
        )
        let snapshotSpaces = [
            DetectedSpace(stableID: "space-a", orderIndex: 1),
            DetectedSpace(stableID: "space-b", orderIndex: 2),
            DetectedSpace(stableID: "space-c", orderIndex: 3)
        ]

        XCTAssertTrue(
            SpaceDetectionResolver.shouldUseAllSpacesForNotesOverlay(
                display: display,
                snapshotSpaces: snapshotSpaces,
                displaySnapshots: [display],
                resolvedOrderIndex: 3,
                liveScreenCount: 2
            )
        )
    }

    func testNotesOverlayUsesAllSpacesForSingleScreenOrphanedUnmatchedSpaces() {
        let liveDisplay = displaySnapshot(
            activeOrderIndex: 1,
            currentStableID: "space-a",
            spaces: [
                DetectedSpace(stableID: "space-a", orderIndex: 1),
                DetectedSpace(stableID: "space-b", orderIndex: 2)
            ]
        )
        let staleDisplay = displaySnapshot(
            activeOrderIndex: 3,
            currentStableID: "space-c",
            screenMatch: "unmatched",
            spaces: [
                DetectedSpace(stableID: "space-c", orderIndex: 3)
            ]
        )
        let snapshotSpaces = [
            DetectedSpace(stableID: "space-a", orderIndex: 1),
            DetectedSpace(stableID: "space-b", orderIndex: 2),
            DetectedSpace(stableID: "space-c", orderIndex: 3)
        ]

        XCTAssertTrue(
            SpaceDetectionResolver.shouldUseAllSpacesForNotesOverlay(
                display: liveDisplay,
                snapshotSpaces: snapshotSpaces,
                displaySnapshots: [liveDisplay, staleDisplay],
                resolvedOrderIndex: 1,
                liveScreenCount: 1
            )
        )
    }

    func testNotesOverlayKeepsMonitorSpacesForLiveMultiDisplayLists() {
        let liveDisplay = displaySnapshot(
            activeOrderIndex: 1,
            currentStableID: "space-a",
            spaces: [
                DetectedSpace(stableID: "space-a", orderIndex: 1),
                DetectedSpace(stableID: "space-b", orderIndex: 2)
            ]
        )
        let otherLiveDisplay = displaySnapshot(
            activeOrderIndex: 3,
            currentStableID: "space-c",
            screenMatch: "exact-display-uuid",
            spaces: [
                DetectedSpace(stableID: "space-c", orderIndex: 3)
            ]
        )
        let snapshotSpaces = [
            DetectedSpace(stableID: "space-a", orderIndex: 1),
            DetectedSpace(stableID: "space-b", orderIndex: 2),
            DetectedSpace(stableID: "space-c", orderIndex: 3)
        ]

        XCTAssertFalse(
            SpaceDetectionResolver.shouldUseAllSpacesForNotesOverlay(
                display: liveDisplay,
                snapshotSpaces: snapshotSpaces,
                displaySnapshots: [liveDisplay, otherLiveDisplay],
                resolvedOrderIndex: 1,
                liveScreenCount: 2
            )
        )
    }

    private func snapshot(
        currentStableID: String? = nil,
        spaceWindowIDs: [String: Set<Int>] = [:]
    ) -> SpaceDetectionResolver.DockSnapshot {
        SpaceDetectionResolver.DockSnapshot(
            spaces: [
                DetectedSpace(stableID: "space-a", orderIndex: 1),
                DetectedSpace(stableID: "space-b", orderIndex: 2),
                DetectedSpace(stableID: "space-c", orderIndex: 3)
            ],
            currentStableID: currentStableID,
            spaceWindowIDs: spaceWindowIDs
        )
    }

    private func displaySnapshot(
        activeOrderIndex: Int?,
        currentStableID: String?,
        screenMatch: String = "exact-display-uuid",
        spaces: [DetectedSpace] = [
            DetectedSpace(stableID: "space-a", orderIndex: 1),
            DetectedSpace(stableID: "space-b", orderIndex: 2),
            DetectedSpace(stableID: "space-c", orderIndex: 3)
        ]
    ) -> DisplaySpaceSnapshot {
        DisplaySpaceSnapshot(
            displayIdentifier: "display-a",
            displayID: 1,
            screenName: "Display A",
            frame: nil,
            screenMatch: screenMatch,
            spaces: spaces,
            currentStableID: currentStableID,
            activeOrderIndex: activeOrderIndex,
            source: "Dock monitor Current Space UUID"
        )
    }
}
