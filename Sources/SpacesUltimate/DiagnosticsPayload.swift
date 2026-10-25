import Foundation

// Shared JSON representations; keep existing field names for API compatibility.
@MainActor
enum DiagnosticsPayload {
    static func space(_ space: SpaceMetadata) -> [String: Any] {
        [
            "id": space.id,
            "stableID": space.stableID ?? NSNull(),
            "orderIndex": space.orderIndex,
            "desktopLabel": space.desktopLabel,
            "name": space.displayName,
            "rawName": space.name,
            "color": space.colorHex,
            "icon": space.icon,
            "note": space.note,
            "shortcut": space.shortcut,
            "assignedApps": space.assignedApps
        ]
    }

    static func nameBinding(_ binding: SpaceNameBindingSummary) -> [String: Any] {
        [
            "orderIndex": binding.orderIndex,
            "displayName": binding.displayName,
            "stableID": binding.stableID ?? NSNull(),
            "mode": binding.mode.rawValue,
            "modeLabel": binding.mode.label,
            "rememberedStableIDCount": binding.rememberedStableIDCount,
            "repairCandidateName": binding.repairCandidateName ?? NSNull()
        ]
    }

    static func detectionDetails(_ details: SpaceDetectionDiagnostics) -> [String: Any] {
        [
            "confidence": details.confidence.rawValue,
            "dockSpaceCount": details.dockSpaceCount,
            "dockMonitorCount": details.dockMonitorCount,
            "dockCurrentStableID": details.dockCurrentStableID ?? NSNull(),
            "dockCurrentStableIDs": details.dockCurrentStableIDs,
            "dockActiveOrderIndex": details.dockActiveOrderIndex ?? NSNull(),
            "visibleWindowIDCount": details.visibleWindowIDCount,
            "uniqueVisibleWindowIDCount": details.uniqueVisibleWindowIDCount,
            "ignoredSharedVisibleWindowIDCount": details.ignoredSharedVisibleWindowIDCount,
            "spaceWindowPropertyCount": details.spaceWindowPropertyCount,
            "windowMatchedOrderIndex": details.windowMatchedOrderIndex ?? NSNull(),
            "windowMatchCandidates": details.windowMatchCandidates.map(windowMatch),
            "notes": details.notes
        ]
    }

    static func windowMatch(_ match: SpaceWindowMatch) -> [String: Any] {
        [
            "stableID": match.stableID,
            "orderIndex": match.orderIndex,
            "matchedVisibleWindowCount": match.matchedVisibleWindowCount,
            "knownWindowCount": match.knownWindowCount
        ]
    }

    static func rules(_ snapshot: RuleSuggestionSnapshot) -> [String: Any] {
        [
            "generatedAt": Self.isoTimestamp.string(from: snapshot.generatedAt),
            "matches": snapshot.matches.map { match in
                [
                    "app": match.appName,
                    "space": match.spaceOrderIndex,
                    "spaceName": match.spaceName,
                    "windowCount": match.windowCount
                ]
            },
            "unassignedVisibleApps": snapshot.unassignedVisibleApps,
            "duplicateAssignments": snapshot.duplicateAssignments
        ]
    }

    static func loginItem(_ state: LoginItemController.State) -> [String: Any] {
        return [
            "supported": state.supported,
            "enabled": state.enabled,
            "status": state.status,
            "canRegister": state.canRegister,
            "requiresUserApproval": state.requiresUserApproval,
            "recoverySuggestion": state.recoverySuggestion,
            "bundlePath": state.bundlePath
        ]
    }

    private static let isoTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
