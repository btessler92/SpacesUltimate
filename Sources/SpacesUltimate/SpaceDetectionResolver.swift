import Foundation

enum SpaceDetectionResolver {
    /// Live identity does not depend on which windows happen to be on a Desktop.
    /// Resolve regular Desktop numbers separately from transient fullscreen cards.
    static func applyingLiveSpace(
        _ stableID: String?,
        spaces: [DetectedSpace],
        to fallback: SpaceDisplayResolution,
        fullscreenSpace: SpaceMetadata? = nil
    ) -> SpaceDisplayResolution {
        guard let stableID else { return fallback }
        var resolution = fallback
        resolution.fullscreenSpace = fullscreenSpace
        if fullscreenSpace != nil {
            resolution.resolvedOrderIndex = nil
            resolution.source = "live macOS fullscreen app Space"
            resolution.confidence = .high
            return resolution
        }
        resolution.resolvedOrderIndex = spaces.first { $0.stableID == stableID }?.orderIndex
        resolution.source = resolution.resolvedOrderIndex == nil
            ? "live macOS Space not in detected Desktop list"
            : "live macOS current Space UUID"
        resolution.confidence = resolution.resolvedOrderIndex == nil ? .fallback : .high
        return resolution
    }

    struct DockSnapshot: Equatable {
        var spaces: [DetectedSpace]
        var currentStableID: String?
        var spaceWindowIDs: [String: Set<Int>]
    }

    struct WindowMatchResult: Equatable {
        var orderIndex: Int?
        var candidates: [SpaceWindowMatch]
        var uniqueVisibleWindowIDCount: Int
        var ignoredSharedVisibleWindowIDCount: Int
    }

    static func activeOrderIndex(from snapshot: DockSnapshot) -> Int? {
        guard let currentStableID = snapshot.currentStableID else { return nil }
        return snapshot.spaces.first { $0.stableID == currentStableID }?.orderIndex
    }

    static func activeOrderIndexFromVisibleWindows(
        in snapshot: DockSnapshot,
        visibleWindowIDs: Set<Int>
    ) -> Int? {
        visibleWindowMatch(in: snapshot, visibleWindowIDs: visibleWindowIDs).orderIndex
    }

    static func displayResolution(
        display: DisplaySpaceSnapshot?,
        snapshot: DockSnapshot,
        visibleWindowIDs: Set<Int>,
        fallbackOrderIndex: Int?
    ) -> SpaceDisplayResolution {
        let windowMatch = visibleWindowMatch(in: snapshot, visibleWindowIDs: visibleWindowIDs)
        let dockOrderIndex = display?.activeOrderIndex
        let trustedDockOrderIndex = display?.screenMatch == "exact-display-uuid" ? dockOrderIndex : nil
        let resolvedOrderIndex: Int?
        let source: String
        let confidence: DetectionConfidence

        if let trustedDockOrderIndex {
            resolvedOrderIndex = trustedDockOrderIndex
            if let windowOrderIndex = windowMatch.orderIndex, windowOrderIndex != trustedDockOrderIndex {
                source = "Dock monitor Current Space UUID (visible-window conflict)"
                confidence = .medium
            } else {
                source = "Dock monitor Current Space UUID"
                confidence = displayResolutionConfidence(for: display)
            }
        } else if let windowOrderIndex = windowMatch.orderIndex {
            resolvedOrderIndex = windowOrderIndex
            source = dockOrderIndex == nil
                ? "screen visible-window Space match"
                : "screen visible-window Space match (untrusted Dock monitor match)"
            confidence = .medium
        } else {
            resolvedOrderIndex = fallbackOrderIndex
            source = fallbackOrderIndex == nil ? "unresolved display fallback" : "global active Space fallback"
            confidence = .fallback
        }

        return SpaceDisplayResolution(
            screenName: display?.screenName,
            displayID: display?.displayID,
            dockDisplayIdentifier: display?.displayIdentifier,
            screenMatch: display?.screenMatch ?? "unmatched",
            resolvedOrderIndex: resolvedOrderIndex,
            source: source,
            confidence: confidence,
            visibleWindowIDCount: visibleWindowIDs.count,
            uniqueVisibleWindowIDCount: windowMatch.uniqueVisibleWindowIDCount,
            ignoredSharedVisibleWindowIDCount: windowMatch.ignoredSharedVisibleWindowIDCount,
            dockCurrentStableID: display?.currentStableID,
            dockResolvedOrderIndex: dockOrderIndex,
            windowMatchedOrderIndex: windowMatch.orderIndex,
            windowMatchCandidates: windowMatch.candidates
        )
    }

    static func mainDisplayResolution(
        display: DisplaySpaceSnapshot?,
        snapshot: DockSnapshot,
        visibleWindowIDs: Set<Int>
    ) -> SpaceDisplayResolution {
        let windowMatch = visibleWindowMatch(in: snapshot, visibleWindowIDs: visibleWindowIDs)
        let dockOrderIndex = display?.activeOrderIndex
        let trustedMainAlias = display?.screenMatch == "main"
        let resolvedOrderIndex: Int?
        let source: String
        let confidence: DetectionConfidence

        if trustedMainAlias,
           let dockOrderIndex,
           let windowOrderIndex = windowMatch.orderIndex,
           windowOrderIndex != dockOrderIndex {
            resolvedOrderIndex = windowOrderIndex
            source = "main display visible-window Space match (stale Dock Main conflict)"
            confidence = .medium
        } else if trustedMainAlias, let dockOrderIndex {
            resolvedOrderIndex = dockOrderIndex
            if let windowOrderIndex = windowMatch.orderIndex, windowOrderIndex != dockOrderIndex {
                source = "main display Dock Current Space UUID (visible-window conflict)"
                confidence = .medium
            } else {
                source = "main display Dock Current Space UUID"
                confidence = .high
            }
        } else if let windowOrderIndex = windowMatch.orderIndex {
            resolvedOrderIndex = windowOrderIndex
            source = dockOrderIndex == nil
                ? "main display visible-window Space match"
                : "main display visible-window Space match (untrusted Dock monitor match)"
            confidence = .medium
        } else {
            resolvedOrderIndex = nil
            source = "main display unresolved"
            confidence = .fallback
        }

        return SpaceDisplayResolution(
            screenName: display?.screenName,
            displayID: display?.displayID,
            dockDisplayIdentifier: display?.displayIdentifier,
            screenMatch: display?.screenMatch ?? "unmatched",
            resolvedOrderIndex: resolvedOrderIndex,
            source: source,
            confidence: confidence,
            visibleWindowIDCount: visibleWindowIDs.count,
            uniqueVisibleWindowIDCount: windowMatch.uniqueVisibleWindowIDCount,
            ignoredSharedVisibleWindowIDCount: windowMatch.ignoredSharedVisibleWindowIDCount,
            dockCurrentStableID: display?.currentStableID,
            dockResolvedOrderIndex: dockOrderIndex,
            windowMatchedOrderIndex: windowMatch.orderIndex,
            windowMatchCandidates: windowMatch.candidates
        )
    }

    static func builtInDisplayResolution(
        display: DisplaySpaceSnapshot?,
        builtInIsMain: Bool,
        snapshot: DockSnapshot,
        visibleWindowIDs: Set<Int>
    ) -> SpaceDisplayResolution {
        let windowMatch = visibleWindowMatch(in: snapshot, visibleWindowIDs: visibleWindowIDs)
        let dockOrderIndex = display?.activeOrderIndex
        let exactDisplayMatch = display?.screenMatch == "exact-display-uuid"
        let trustedMainAlias = builtInIsMain && display?.screenMatch == "main"
        let dockCanIdentifyBuiltIn = exactDisplayMatch || trustedMainAlias
        let resolvedOrderIndex: Int?
        let source: String
        let confidence: DetectionConfidence

        if dockCanIdentifyBuiltIn,
           let dockOrderIndex,
           let windowOrderIndex = windowMatch.orderIndex,
           windowOrderIndex != dockOrderIndex,
           trustedMainAlias,
           !exactDisplayMatch {
            resolvedOrderIndex = windowOrderIndex
            source = "built-in visible-window Space match (stale Dock Main conflict)"
            confidence = .medium
        } else if dockCanIdentifyBuiltIn, let dockOrderIndex {
            resolvedOrderIndex = dockOrderIndex
            if let windowOrderIndex = windowMatch.orderIndex, windowOrderIndex != dockOrderIndex {
                source = "built-in Dock Current Space UUID (visible-window conflict)"
                confidence = .medium
            } else if exactDisplayMatch {
                source = "built-in Dock Current Space UUID"
                confidence = .high
            } else {
                source = "built-in Dock Main Current Space UUID"
                confidence = .medium
            }
        } else if let windowOrderIndex = windowMatch.orderIndex {
            resolvedOrderIndex = windowOrderIndex
            source = dockOrderIndex == nil
                ? "built-in visible-window Space match"
                : "built-in visible-window Space match (untrusted Dock monitor match)"
            confidence = .medium
        } else {
            resolvedOrderIndex = nil
            source = "built-in display unresolved"
            confidence = .fallback
        }

        return SpaceDisplayResolution(
            screenName: display?.screenName,
            displayID: display?.displayID,
            dockDisplayIdentifier: display?.displayIdentifier,
            screenMatch: display?.screenMatch ?? "unmatched",
            resolvedOrderIndex: resolvedOrderIndex,
            source: source,
            confidence: confidence,
            visibleWindowIDCount: visibleWindowIDs.count,
            uniqueVisibleWindowIDCount: windowMatch.uniqueVisibleWindowIDCount,
            ignoredSharedVisibleWindowIDCount: windowMatch.ignoredSharedVisibleWindowIDCount,
            dockCurrentStableID: display?.currentStableID,
            dockResolvedOrderIndex: dockOrderIndex,
            windowMatchedOrderIndex: windowMatch.orderIndex,
            windowMatchCandidates: windowMatch.candidates
        )
    }

    static func visibleWindowMatch(
        in snapshot: DockSnapshot,
        visibleWindowIDs: Set<Int>
    ) -> WindowMatchResult {
        guard !snapshot.spaces.isEmpty, !snapshot.spaceWindowIDs.isEmpty, !visibleWindowIDs.isEmpty else {
            return WindowMatchResult(
                orderIndex: nil,
                candidates: [],
                uniqueVisibleWindowIDCount: 0,
                ignoredSharedVisibleWindowIDCount: 0
            )
        }

        let windowFrequency = snapshot.spaceWindowIDs.values.reduce(into: [Int: Int]()) { frequencies, windowIDs in
            for windowID in windowIDs {
                frequencies[windowID, default: 0] += 1
            }
        }
        let uniqueVisibleWindowIDs = visibleWindowIDs.filter { windowFrequency[$0] == 1 }
        let ignoredSharedVisibleWindowIDCount = visibleWindowIDs.filter { (windowFrequency[$0] ?? 0) > 1 }.count
        guard !uniqueVisibleWindowIDs.isEmpty else {
            return WindowMatchResult(
                orderIndex: nil,
                candidates: [],
                uniqueVisibleWindowIDCount: 0,
                ignoredSharedVisibleWindowIDCount: ignoredSharedVisibleWindowIDCount
            )
        }

        let orderByStableID = Dictionary(
            uniqueKeysWithValues: snapshot.spaces.compactMap { space -> (String, Int)? in
                guard let stableID = space.stableID else { return nil }
                return (stableID, space.orderIndex)
            }
        )

        let candidates = snapshot.spaceWindowIDs.compactMap { stableID, windowIDs -> SpaceWindowMatch? in
            guard let orderIndex = orderByStableID[stableID] else { return nil }
            let count = windowIDs.intersection(uniqueVisibleWindowIDs).count
            return count > 0
                ? SpaceWindowMatch(
                    stableID: stableID,
                    orderIndex: orderIndex,
                    matchedVisibleWindowCount: count,
                    knownWindowCount: windowIDs.count
                )
                : nil
        }
        .sorted {
            if $0.matchedVisibleWindowCount != $1.matchedVisibleWindowCount {
                return $0.matchedVisibleWindowCount > $1.matchedVisibleWindowCount
            }
            return $0.orderIndex < $1.orderIndex
        }
        guard let best = candidates.first else {
            return WindowMatchResult(
                orderIndex: nil,
                candidates: [],
                uniqueVisibleWindowIDCount: uniqueVisibleWindowIDs.count,
                ignoredSharedVisibleWindowIDCount: ignoredSharedVisibleWindowIDCount
            )
        }
        let tiedBestCount = candidates.filter { $0.matchedVisibleWindowCount == best.matchedVisibleWindowCount }.count
        return WindowMatchResult(
            orderIndex: tiedBestCount == 1 ? best.orderIndex : nil,
            candidates: candidates,
            uniqueVisibleWindowIDCount: uniqueVisibleWindowIDs.count,
            ignoredSharedVisibleWindowIDCount: ignoredSharedVisibleWindowIDCount
        )
    }

    static func detectionSource(
        hasDetectedSpaces: Bool,
        hasDockActiveSpace: Bool,
        hasWindowMatchedActiveSpace: Bool
    ) -> String {
        if hasDetectedSpaces && hasDockActiveSpace {
            return "Dock preferences Current Space UUID"
        }
        if hasDetectedSpaces && hasWindowMatchedActiveSpace {
            return "Dock Space Properties visible window IDs"
        }
        if hasDetectedSpaces {
            return "Dock preferences + CGWindow heuristic"
        }
        return "manual/order fallback"
    }

    static func shouldUseAllSpacesForNotesOverlay(
        display: DisplaySpaceSnapshot,
        snapshotSpaces: [DetectedSpace],
        displaySnapshots: [DisplaySpaceSnapshot],
        resolvedOrderIndex: Int?,
        liveScreenCount: Int
    ) -> Bool {
        let monitorOrderIndexes = Set(display.spaces.map(\.orderIndex))
        guard !monitorOrderIndexes.isEmpty else { return true }

        if let resolvedOrderIndex, !monitorOrderIndexes.contains(resolvedOrderIndex) {
            return true
        }

        guard liveScreenCount == 1 else { return false }

        let allOrderIndexes = Set(snapshotSpaces.map(\.orderIndex))
        let missingOrderIndexes = allOrderIndexes.subtracting(monitorOrderIndexes)
        guard !missingOrderIndexes.isEmpty else { return false }

        return missingOrderIndexes.allSatisfy { orderIndex in
            displaySnapshots.contains { snapshot in
                snapshot.screenMatch == "unmatched"
                    && snapshot.spaces.contains { $0.orderIndex == orderIndex }
            }
        }
    }

    private static func displayResolutionConfidence(for display: DisplaySpaceSnapshot?) -> DetectionConfidence {
        guard display?.activeOrderIndex != nil, display?.currentStableID != nil else {
            return .fallback
        }
        switch display?.screenMatch {
        case "exact-display-uuid", "main":
            return .high
        case "index-fallback":
            return .medium
        default:
            return .low
        }
    }
}
