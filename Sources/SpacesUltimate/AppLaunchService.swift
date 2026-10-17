import AppKit
import Foundation

@MainActor
final class AppLaunchService {
    struct LaunchResult: Equatable {
        var appName: String
        var launched: Bool
        var path: String?
        var message: String
    }

    func launchAssignedApps(for space: SpaceMetadata) -> [LaunchResult] {
        let apps = normalizedApps(space.assignedApps)
        guard !apps.isEmpty else {
            return [
                LaunchResult(
                    appName: space.displayName,
                    launched: false,
                    path: nil,
                    message: "Desktop \(space.orderIndex) has no assigned apps."
                )
            ]
        }

        return apps.map(launchApp(named:))
    }

    private func launchApp(named name: String) -> LaunchResult {
        guard let url = applicationURL(for: name) else {
            let message = "Could not find an installed app named '\(name)'."
            AppLog.shared.warning(message)
            return LaunchResult(appName: name, launched: false, path: nil, message: message)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            Task { @MainActor in
                if let error {
                    AppLog.shared.warning("Launch failed for \(name): \(error.localizedDescription)")
                } else {
                    AppLog.shared.info("Launch requested for \(app?.localizedName ?? name) at \(url.path)")
                }
            }
        }

        return LaunchResult(appName: name, launched: true, path: url.path, message: "Launch requested.")
    }

    private func applicationURL(for name: String) -> URL? {
        let expanded = (name as NSString).expandingTildeInPath
        if expanded.contains("/") {
            let url = URL(fileURLWithPath: expanded)
            return isApplication(url) ? url : nil
        }

        if name.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            return url
        }

        let candidates = applicationSearchRoots().compactMap { root in
            findApplication(named: name, under: root)
        }
        return candidates.sorted { first, second in
            first.pathComponents.count == second.pathComponents.count
                ? first.path.localizedCaseInsensitiveCompare(second.path) == .orderedAscending
                : first.pathComponents.count < second.pathComponents.count
        }.first
    }

    private func applicationSearchRoots() -> [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
    }

    private func findApplication(named name: String, under root: URL) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return nil }

        let expected = normalizedAppName(name)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard isApplication(url), normalizedAppName(url.deletingPathExtension().lastPathComponent) == expected else {
                continue
            }
            return url
        }
        return nil
    }

    private func isApplication(_ url: URL) -> Bool {
        url.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame
    }

    private func normalizedApps(_ apps: [String]) -> [String] {
        var seen = Set<String>()
        return apps.compactMap { app in
            let trimmed = app.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = normalizedAppName(trimmed)
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }

    private func normalizedAppName(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive, .anchored])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
