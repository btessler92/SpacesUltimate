import Foundation

@MainActor
final class RuleEngine {
    private let store: SpaceStore
    private let scanner: WindowScanner

    init(store: SpaceStore, scanner: WindowScanner) {
        self.store = store
        self.scanner = scanner
    }

    func snapshot() -> RuleSuggestionSnapshot {
        snapshot(for: scanner.scanVisibleWindows())
    }

    func snapshot(for windows: [ScannedWindow]) -> RuleSuggestionSnapshot {
        let visibleCounts = Dictionary(grouping: windows, by: { $0.appName.lowercased() })
            .mapValues(\.count)
        let visibleNamesByKey = Dictionary(
            windows.map { ($0.appName.lowercased(), $0.appName) },
            uniquingKeysWith: { first, _ in first }
        )
        let assignments = assignmentsByApp()

        let matches = visibleCounts.compactMap { visibleKey, count -> RuleMatch? in
            guard let assignmentKey = matchingAssignmentKey(for: visibleKey, in: assignments.keys),
                  let firstSpace = assignments[assignmentKey]?.sorted(by: { $0.orderIndex < $1.orderIndex }).first else {
                return nil
            }
            return RuleMatch(
                appName: visibleNamesByKey[visibleKey] ?? visibleKey,
                spaceOrderIndex: firstSpace.orderIndex,
                spaceName: firstSpace.displayName,
                windowCount: count
            )
        }
        .sorted {
            if $0.spaceOrderIndex == $1.spaceOrderIndex {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.spaceOrderIndex < $1.spaceOrderIndex
        }

        let unassigned = visibleNamesByKey
            .filter { key, _ in matchingAssignmentKey(for: key, in: assignments.keys) == nil }
            .map(\.value)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let duplicates = assignments
            .filter { _, spaces in spaces.count > 1 }
            .mapValues { spaces in spaces.map(\.orderIndex).sorted() }

        return RuleSuggestionSnapshot(
            generatedAt: Date(),
            matches: matches,
            unassignedVisibleApps: unassigned,
            duplicateAssignments: duplicates
        )
    }

    func assignUnassignedVisibleApps(to orderIndex: Int) -> [String] {
        let snapshot = snapshot()
        guard !snapshot.unassignedVisibleApps.isEmpty else { return [] }

        var space = store.space(orderIndex: orderIndex)
        let existingKeys = Set(space.assignedApps.map(normalizedAppKey))
        var added: [String] = []
        for app in snapshot.unassignedVisibleApps {
            let key = normalizedAppKey(app)
            guard !key.isEmpty, !existingKeys.contains(key), !added.map(normalizedAppKey).contains(key) else {
                continue
            }
            added.append(app)
        }

        guard !added.isEmpty else { return [] }
        space.assignedApps.append(contentsOf: added)
        space.assignedApps = normalizedAssignedApps(space.assignedApps)
        store.update(space)
        AppLog.shared.info("Assigned visible app rule(s) to Desktop \(orderIndex): \(added.joined(separator: ", "))")
        return added
    }

    func resolveDuplicateAssignments() -> [String: [Int]] {
        let snapshot = snapshot()
        guard !snapshot.duplicateAssignments.isEmpty else { return [:] }

        let duplicateKeys = Set(snapshot.duplicateAssignments.keys)
        let spaces = store.spaces.map { space -> SpaceMetadata in
            var copy = space
            copy.assignedApps = space.assignedApps.filter { app in
                let key = normalizedAppKey(app)
                guard duplicateKeys.contains(key),
                      let keepSpace = snapshot.duplicateAssignments[key]?.min() else {
                    return true
                }
                return space.orderIndex == keepSpace
            }
            return copy
        }

        store.updateSpaces(spaces)
        AppLog.shared.info("Resolved duplicate app rules: \(duplicateKeys.sorted().joined(separator: ", "))")
        return snapshot.duplicateAssignments
    }

    private func assignmentsByApp() -> [String: [SpaceMetadata]] {
        var assignments: [String: [SpaceMetadata]] = [:]
        for space in store.spaces {
            for app in space.assignedApps {
                let key = normalizedAppKey(app)
                guard !key.isEmpty else { continue }
                assignments[key, default: []].append(space)
            }
        }
        return assignments
    }

    private func matchingAssignmentKey(for visibleKey: String, in assignmentKeys: Dictionary<String, [SpaceMetadata]>.Keys) -> String? {
        assignmentKeys
            .filter { key in visibleKey == key || visibleKey.contains(key) || key.contains(visibleKey) }
            .sorted { first, second in
                if first.count == second.count { return first < second }
                return first.count > second.count
            }
            .first
    }

    private func normalizedAssignedApps(_ apps: [String]) -> [String] {
        var seen = Set<String>()
        return apps.compactMap { app in
            let trimmed = app.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedAppKey(trimmed)
            guard !trimmed.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }

    private func normalizedAppKey(_ app: String) -> String {
        app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
