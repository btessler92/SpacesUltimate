import AppKit
import Foundation

@MainActor
final class SpaceStore {
    private(set) var config: SpaceConfig
    let configURL: URL
    var onChange: ((SpaceConfig) -> Void)?

    init(fileManager: FileManager = .default) {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["SPACESULTIMATE_CONFIG_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let preferred = support.appendingPathComponent("SpacesUltimate", isDirectory: true)
            if (try? fileManager.createDirectory(at: preferred, withIntermediateDirectories: true)) != nil {
                directory = preferred
            } else {
                directory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                    .appendingPathComponent(".spacesultimate", isDirectory: true)
            }
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        configURL = directory.appendingPathComponent("spaces-config.json")

        if let data = try? Data(contentsOf: configURL) {
            if let decoded = try? JSONDecoder().decode(SpaceConfig.self, from: data) {
                config = decoded
            } else {
                config = .defaults()
                preserveInvalidConfig(data)
            }
        } else {
            config = .defaults()
        }
        normalizeOrder()
        save()
    }

    var spaces: [SpaceMetadata] {
        config.spaces.sorted { $0.orderIndex < $1.orderIndex }
    }

    func space(orderIndex: Int) -> SpaceMetadata {
        spaces.first { $0.orderIndex == orderIndex } ?? SpaceConfig.defaults(spaceCount: orderIndex).spaces[orderIndex - 1]
    }

    func update(_ space: SpaceMetadata) {
        if let index = config.spaces.firstIndex(where: { $0.id == space.id }) {
            config.spaces[index] = space
        }
        normalizeOrder()
        _ = archiveStableMetadata(config.spaces)
        saveAndNotify()
    }

    func updateSpaces(_ spaces: [SpaceMetadata]) {
        config.spaces = spaces
        normalizeOrder()
        _ = archiveStableMetadata(config.spaces)
        saveAndNotify()
    }

    func updateSettings(_ settings: AppSettings) {
        config.settings = settings.normalized
        saveAndNotify()
    }

    var preferenceDefaults: PreferenceDefaults {
        config.savedPreferenceDefaults ?? .factory
    }

    func saveCurrentPreferencesAsDefault(launchAtLogin: Bool) {
        createBackup(reason: "before-saving-preference-default")
        config.savedPreferenceDefaults = PreferenceDefaults(
            settings: config.settings.normalized, launchAtLogin: launchAtLogin, savedAt: Date())
        saveAndNotify()
    }

    func restorePreferences(from preset: PreferenceDefaults) {
        createBackup(reason: "before-restoring-preferences")
        config.settings = preset.settingsToApply(preserving: config.settings)
        saveAndNotify()
    }

    func reconcile(with detected: [DetectedSpace], preserveStableIdentity: Bool = false) {
        guard !detected.isEmpty else { return }

        let existingSpaces = spaces
        let historyChanged = archiveStableMetadata(existingSpaces)
        let shouldRefreshGeneratedColors = Self.usesGeneratedColors(existingSpaces)
        var existingByStableID = Dictionary(
            existingSpaces.compactMap { space in
                space.stableID.map { ($0, space) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var existingByOrder = Dictionary(
            existingSpaces.map { ($0.orderIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var next: [SpaceMetadata] = []
        for detectedSpace in detected.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            var metadata: SpaceMetadata
            if let stableID = detectedSpace.stableID, let matched = existingByStableID.removeValue(forKey: stableID) {
                metadata = matched
            } else if detectedSpace.stableID != nil,
                      let fallbackMatch = existingByOrder[detectedSpace.orderIndex],
                      fallbackMatch.stableID == nil {
                metadata = fallbackMatch
                existingByOrder.removeValue(forKey: detectedSpace.orderIndex)
            } else if let stableID = detectedSpace.stableID, let remembered = config.stableSpaceHistory[stableID] {
                metadata = remembered
            } else if !preserveStableIdentity, let matched = existingByOrder.removeValue(forKey: detectedSpace.orderIndex) {
                metadata = matched
            } else {
                metadata = SpaceConfig.defaults(spaceCount: detectedSpace.orderIndex).spaces[detectedSpace.orderIndex - 1]
            }
            metadata.stableID = detectedSpace.stableID
            metadata.id = detectedSpace.stableID ?? "order-\(detectedSpace.orderIndex)"
            metadata.orderIndex = detectedSpace.orderIndex
            if Self.isAutomaticDesktopName(metadata.name) {
                metadata.name = "Desktop \(detectedSpace.orderIndex)"
            }
            next.append(metadata)
        }

        if shouldRefreshGeneratedColors {
            refreshGeneratedColors(in: &next)
        }

        if next != config.spaces || historyChanged {
            config.spaces = next
            normalizeOrder()
            _ = archiveStableMetadata(config.spaces)
            saveAndNotify()
        }
    }

    func setActiveOrderIndex(_ index: Int) {
        guard config.lastKnownActiveOrderIndex != index else { return }
        config.lastKnownActiveOrderIndex = index
        saveAndNotify()
    }

    func nameBindingSummaries() -> [SpaceNameBindingSummary] {
        spaces.map { space in
            SpaceNameBindingSummary(
                orderIndex: space.orderIndex,
                displayName: space.displayName,
                stableID: space.stableID,
                mode: space.stableID == nil ? .orderFallback : .stableID,
                rememberedStableIDCount: rememberedStableSpaces(forOrderIndex: space.orderIndex).count,
                repairCandidateName: repairCandidate(for: space)?.displayName
            )
        }
    }

    @discardableResult
    func repairOrderFallbackNamesFromHistory() -> [Int: String] {
        var repaired: [Int: String] = [:]
        let updated = spaces.map { space -> SpaceMetadata in
            guard let candidate = repairCandidate(for: space) else { return space }
            var copy = space
            copy.name = candidate.name
            copy.colorHex = candidate.colorHex
            copy.icon = candidate.icon
            copy.note = candidate.note
            copy.shortcut = candidate.shortcut
            copy.assignedApps = candidate.assignedApps
            repaired[space.orderIndex] = candidate.displayName
            return copy
        }

        guard !repaired.isEmpty else { return [:] }
        createBackup(reason: "before-name-repair")
        config.spaces = updated
        normalizeOrder()
        saveAndNotify()
        AppLog.shared.info("Repaired Space name(s) from stable history: \(repaired.keys.sorted().map(String.init).joined(separator: ", "))")
        return repaired
    }

    func resetNames() {
        createBackup(reason: "before-reset")
        config.spaces = spaces.map { space in
            var copy = space
            copy.name = "Desktop \(space.orderIndex)"
            copy.icon = ""
            copy.note = ""
            copy.shortcut = ""
            copy.assignedApps = []
            return copy
        }
        _ = archiveStableMetadata(config.spaces)
        saveAndNotify()
    }

    func exportConfig(to url: URL) throws {
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    func importConfig(from url: URL) throws {
        createBackup(reason: "before-import")
        let data = try Data(contentsOf: url)
        config = try JSONDecoder().decode(SpaceConfig.self, from: data)
        normalizeOrder()
        saveAndNotify()
    }

    var backupsDirectory: URL {
        configURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    var invalidConfigDirectory: URL {
        configURL
            .deletingLastPathComponent()
            .appendingPathComponent("InvalidConfigs", isDirectory: true)
    }

    @discardableResult
    func createBackup(reason: String) -> URL? {
        do {
            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let stamp = Self.backupDateFormatter.string(from: Date())
            let safeReason = reason
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"[^A-Za-z0-9_-]+"#, with: "-", options: .regularExpression)
            let url = backupsDirectory.appendingPathComponent("spaces-config-\(stamp)-\(safeReason).json")
            try encoder.encode(config).write(to: url, options: .atomic)
            pruneBackups(keeping: 20)
            AppLog.shared.info("Created config backup: \(url.path)")
            return url
        } catch {
            AppLog.shared.warning("Could not create config backup: \(error.localizedDescription)")
            return nil
        }
    }

    func listBackups() -> [URL] {
        listJSONFiles(in: backupsDirectory)
    }

    func listInvalidConfigs() -> [URL] {
        listJSONFiles(in: invalidConfigDirectory)
    }

    func restoreLatestBackup() throws {
        guard let latest = listBackups().first else {
            throw ConfigRecoveryError.noBackups
        }
        try restoreBackup(from: latest)
    }

    func restoreBackup(named fileName: String) throws {
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        let url = backupsDirectory.appendingPathComponent(safeName)
        guard listBackups().contains(where: { $0.lastPathComponent == safeName }) else {
            throw ConfigRecoveryError.backupNotFound
        }
        try restoreBackup(from: url)
    }

    private func restoreBackup(from url: URL) throws {
        createBackup(reason: "before-restore")
        let data = try Data(contentsOf: url)
        config = try JSONDecoder().decode(SpaceConfig.self, from: data)
        normalizeOrder()
        saveAndNotify()
        AppLog.shared.info("Restored config backup: \(url.path)")
    }

    private func preserveInvalidConfig(_ data: Data) {
        do {
            try FileManager.default.createDirectory(at: invalidConfigDirectory, withIntermediateDirectories: true)
            let stamp = Self.backupDateFormatter.string(from: Date())
            let url = invalidConfigDirectory.appendingPathComponent("spaces-config-invalid-\(stamp).json")
            try data.write(to: url, options: .atomic)
            pruneInvalidConfigs(keeping: 10)
            AppLog.shared.warning("Preserved invalid config before resetting to defaults: \(url.path)")
        } catch {
            AppLog.shared.error("Could not preserve invalid config: \(error.localizedDescription)")
        }
    }

    private func normalizeOrder() {
        if config.spaces.isEmpty {
            config = .defaults()
        }

        config.spaces.sort { $0.orderIndex < $1.orderIndex }
        var usedIDs = Set<String>()
        for index in config.spaces.indices {
            config.spaces[index].orderIndex = index + 1
            if Self.isAutomaticDesktopName(config.spaces[index].name) {
                config.spaces[index].name = "Desktop \(index + 1)"
            }
            let fallbackID = config.spaces[index].stableID ?? "order-\(index + 1)"
            if config.spaces[index].id.isEmpty || usedIDs.contains(config.spaces[index].id) {
                config.spaces[index].id = usedIDs.contains(fallbackID) ? "order-\(index + 1)" : fallbackID
            }
            usedIDs.insert(config.spaces[index].id)
        }
        normalizeGeneratedColors()
        normalizeStableHistory()
        config.settings = config.settings.normalized
        if var preset = config.savedPreferenceDefaults {
            preset.settings = preset.settings.normalized
            config.savedPreferenceDefaults = preset
        }
        config.lastKnownActiveOrderIndex = min(max(config.lastKnownActiveOrderIndex, 1), config.spaces.count)
    }

    private func normalizeGeneratedColors() {
        guard Self.usesGeneratedColors(config.spaces) else { return }
        refreshGeneratedColors(in: &config.spaces)
    }

    private func refreshGeneratedColors(in spaces: inout [SpaceMetadata]) {
        let count = spaces.count
        for index in spaces.indices {
            spaces[index].colorHex = SpaceConfig.spectrumColorHex(orderIndex: index + 1, totalCount: count)
        }
    }

    private static func usesGeneratedColors(_ spaces: [SpaceMetadata]) -> Bool {
        guard !spaces.isEmpty else { return true }
        let colors = spaces.map { Self.normalizedColorHex($0.colorHex) }
        let generatedFlags = colors.enumerated().map { index, color in
            legacyDefaultColorHexes.contains(color)
                || color == normalizedColorHex(SpaceConfig.spectrumColorHex(orderIndex: index + 1, totalCount: spaces.count))
                || color == normalizedColorHex(legacySpectrumColorHex(orderIndex: index + 1, totalCount: spaces.count))
        }
        let legacyColors = colors.filter { legacyDefaultColorHexes.contains($0) }
        let hasRepeatedLegacyColor = Set(legacyColors).count < legacyColors.count
        let hasRepeatedColor = Set(colors).count < colors.count
        return generatedFlags.allSatisfy { $0 } || hasRepeatedLegacyColor || hasRepeatedColor
    }

    private static func normalizedColorHex(_ colorHex: String) -> String {
        let cleaned = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        return cleaned.count == 6 ? "#\(cleaned)" : colorHex.uppercased()
    }

    private static func legacySpectrumColorHex(orderIndex: Int, totalCount: Int) -> String {
        let count = max(1, totalCount)
        let position = count == 1 ? 0 : Double(max(0, orderIndex - 1)) / Double(count - 1)
        let hue = min(0.82, max(0, position * 0.82))
        return NSColor(calibratedHue: CGFloat(hue), saturation: 0.72, brightness: 0.92, alpha: 1).hexString
    }

    private static let legacyDefaultColorHexes: Set<String> = [
        "#2F80ED",
        "#27AE60",
        "#EB5757",
        "#F2C94C",
        "#9B51E0",
        "#00A8A8"
    ]

    @discardableResult
    private func archiveStableMetadata(_ spaces: [SpaceMetadata]) -> Bool {
        let previous = config.stableSpaceHistory
        for space in spaces {
            guard let stableID = space.stableID, !stableID.isEmpty else { continue }
            config.stableSpaceHistory[stableID] = space
        }
        normalizeStableHistory()
        return previous != config.stableSpaceHistory
    }

    private func normalizeStableHistory() {
        config.stableSpaceHistory = Dictionary(
            uniqueKeysWithValues: config.stableSpaceHistory.compactMap { stableID, space -> (String, SpaceMetadata)? in
                let trimmedID = stableID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedID.isEmpty else { return nil }
                var copy = space
                copy.stableID = trimmedID
                copy.id = trimmedID
                if copy.orderIndex < 1 {
                    copy.orderIndex = 1
                }
                return (trimmedID, copy)
            }
        )
    }

    private static func isAutomaticDesktopName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("Desktop ") else { return false }
        return Int(trimmed.dropFirst("Desktop ".count)) != nil
    }

    private func repairCandidate(for space: SpaceMetadata) -> SpaceMetadata? {
        guard space.stableID == nil, Self.isAutomaticDesktopName(space.name) else { return nil }
        return rememberedStableSpaces(forOrderIndex: space.orderIndex)
            .filter { !Self.isAutomaticDesktopName($0.name) }
            .sorted { first, second in
                let firstID = first.stableID ?? ""
                let secondID = second.stableID ?? ""
                return firstID.localizedCaseInsensitiveCompare(secondID) == .orderedAscending
            }
            .first
    }

    private func rememberedStableSpaces(forOrderIndex orderIndex: Int) -> [SpaceMetadata] {
        config.stableSpaceHistory.values.filter { $0.orderIndex == orderIndex }
    }

    private func saveAndNotify() {
        save()
        onChange?(config)
    }

    private func save() {
        do {
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            AppLog.shared.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    private func pruneBackups(keeping count: Int) {
        let oldBackups = Array(listBackups().dropFirst(count))
        for url in oldBackups {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func pruneInvalidConfigs(keeping count: Int) {
        let oldFiles = Array(listInvalidConfigs().dropFirst(count))
        for url in oldFiles {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func listJSONFiles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { first, second in
                modificationDate(first) > modificationDate(second)
            }
    }

    private func modificationDate(_ url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    enum ConfigRecoveryError: LocalizedError {
        case noBackups
        case backupNotFound

        var errorDescription: String? {
            switch self {
            case .noBackups:
                "No SpacesUltimate config backups are available."
            case .backupNotFound:
                "The requested SpacesUltimate config backup was not found."
            }
        }
    }
}
