import AppKit
import CoreGraphics
import Foundation

@MainActor
final class SpaceDetector {
    private let store: SpaceStore
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var pendingSpaceChangeRefreshes: [Task<Void, Never>] = []
    private(set) var lastSnapshot: SpaceDetectionSnapshot?

    var onActiveSpaceChanged: ((SpaceDetectionSnapshot) -> Void)?
    var onSnapshot: ((SpaceDetectionSnapshot) -> Void)?

    init(store: SpaceStore) {
        self.store = store
    }

    func start() {
        refresh(reason: "startup")
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleActiveSpaceChangedNotification()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "poll")
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingSpaceChangeRefreshes.forEach { $0.cancel() }
        pendingSpaceChangeRefreshes = []
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func handleActiveSpaceChangedNotification() {
        refresh(reason: "NSWorkspace active Space changed")
        pendingSpaceChangeRefreshes.forEach { $0.cancel() }
        pendingSpaceChangeRefreshes = [
            scheduledSettlingRefresh(after: 0.25, reason: "NSWorkspace active Space changed settled 250ms"),
            scheduledSettlingRefresh(after: 0.90, reason: "NSWorkspace active Space changed settled 900ms")
        ]
    }

    private func scheduledSettlingRefresh(after seconds: TimeInterval, reason: String) -> Task<Void, Never> {
        Task { [weak self] in
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refresh(reason: reason)
            }
        }
    }

    func refresh(reason: String = "manual refresh") {
        let dockSnapshot = readDockSpaces()
        let detectedSpaces = dockSnapshot.spaces
        let visibleWindowIDs = currentScreenWindowIDs()
        let windowMatch = SpaceDetectionResolver.visibleWindowMatch(
            in: dockSnapshot.resolverSnapshot,
            visibleWindowIDs: visibleWindowIDs
        )
        let windowMatchedActive = windowMatch.orderIndex
        let dockActive = SpaceDetectionResolver.activeOrderIndex(from: dockSnapshot.resolverSnapshot)
        let active = dockActive ?? windowMatchedActive ?? inferActiveSpace(maxCount: max(detectedSpaces.count, store.spaces.count))
        let displayResolutions = displayResolutions(dockSnapshot: dockSnapshot)
        let source = SpaceDetectionResolver.detectionSource(
            hasDetectedSpaces: !detectedSpaces.isEmpty,
            hasDockActiveSpace: dockActive != nil,
            hasWindowMatchedActiveSpace: windowMatchedActive != nil
        )
        let snapshot = SpaceDetectionSnapshot(
            spaces: detectedSpaces.isEmpty ? fallbackSpaces() : detectedSpaces,
            activeOrderIndex: active,
            displaySnapshots: dockSnapshot.displaySnapshots,
            displayResolutions: displayResolutions,
            source: source,
            eventDescription: reason,
            date: Date(),
            diagnostics: detectionDiagnostics(
                dockSnapshot: dockSnapshot,
                dockActive: dockActive,
                windowMatch: windowMatch,
                visibleWindowIDCount: visibleWindowIDs.count,
                active: active,
                source: source
            )
        )

        store.reconcile(with: snapshot.spaces)
        if let active {
            store.setActiveOrderIndex(active)
        }

        let changed = snapshot.activeOrderIndex != lastSnapshot?.activeOrderIndex
            || Self.displayResolutionSummary(snapshot.displayResolutions) != Self.displayResolutionSummary(lastSnapshot?.displayResolutions ?? [])
        lastSnapshot = snapshot
        onSnapshot?(snapshot)
        if changed {
            AppLog.shared.info("Active Space changed to \(snapshot.activeOrderIndex.map(String.init) ?? "unknown") via \(snapshot.source)")
            onActiveSpaceChanged?(snapshot)
        }
    }

    func activeOrderIndex(for screen: NSScreen?) -> Int {
        displayResolution(for: screen).resolvedOrderIndex ?? store.config.lastKnownActiveOrderIndex
    }

    func builtInDisplayStatus() -> (screen: NSScreen?, resolution: SpaceDisplayResolution) {
        let screen = Self.builtInDisplayScreen()
        let fallback = SpaceDisplayResolution(
            screenName: screen?.localizedName,
            displayID: screen.flatMap(Self.displayID(for:)),
            dockDisplayIdentifier: nil,
            screenMatch: "unmatched",
            resolvedOrderIndex: nil,
            source: "built-in display unavailable",
            confidence: .fallback,
            visibleWindowIDCount: 0,
            uniqueVisibleWindowIDCount: 0,
            ignoredSharedVisibleWindowIDCount: 0,
            dockCurrentStableID: nil,
            dockResolvedOrderIndex: nil,
            windowMatchedOrderIndex: nil,
            windowMatchCandidates: []
        )

        guard let screen, let snapshot = lastSnapshot else {
            return (screen, fallback)
        }

        let visibleWindowIDs = currentScreenWindowIDs(on: screen)
        var resolution = SpaceDetectionResolver.builtInDisplayResolution(
            display: builtInDisplaySnapshot(for: screen, in: snapshot.displaySnapshots),
            builtInIsMain: Self.isMainScreen(screen),
            snapshot: resolverSnapshot(from: snapshot),
            visibleWindowIDs: visibleWindowIDs
        )
        if resolution.screenName == nil {
            resolution.screenName = screen.localizedName
        }
        if resolution.displayID == nil {
            resolution.displayID = Self.displayID(for: screen)
        }
        return (screen, resolution)
    }

    func mainDisplayStatus() -> (screen: NSScreen?, resolution: SpaceDisplayResolution) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen, let snapshot = lastSnapshot else {
            return (screen, displayResolution(for: screen))
        }

        if let mainDisplay = mainDisplaySnapshot(in: snapshot.displaySnapshots) {
            var resolution = SpaceDetectionResolver.mainDisplayResolution(
                display: mainDisplay,
                snapshot: resolverSnapshot(from: snapshot),
                visibleWindowIDs: currentScreenWindowIDs(on: screen)
            )
            if resolution.screenName == nil {
                resolution.screenName = screen.localizedName
            }
            if resolution.displayID == nil {
                resolution.displayID = Self.displayID(for: screen)
            }
            return (screen, resolution)
        }

        let resolution = displayResolution(for: screen)
        return (screen, resolution)
    }

    func displayResolution(for screen: NSScreen?) -> SpaceDisplayResolution {
        let fallback = SpaceDisplayResolution(
            screenName: screen?.localizedName,
            displayID: screen.flatMap(Self.displayID(for:)),
            dockDisplayIdentifier: nil,
            screenMatch: "unmatched",
            resolvedOrderIndex: nil,
            source: "no detection snapshot",
            confidence: .fallback,
            visibleWindowIDCount: 0,
            uniqueVisibleWindowIDCount: 0,
            ignoredSharedVisibleWindowIDCount: 0,
            dockCurrentStableID: nil,
            dockResolvedOrderIndex: nil,
            windowMatchedOrderIndex: nil,
            windowMatchCandidates: []
        )

        guard let screen, let snapshot = lastSnapshot else {
            return fallback
        }

        if let displayID = Self.displayID(for: screen),
           let exact = snapshot.displayResolutions.first(where: { $0.displayID == displayID }) {
            return exact
        }

        let candidates = snapshot.displaySnapshots.filter { display in
            guard let frame = display.frame else { return false }
            return frame.intersection(screen.frame).width * frame.intersection(screen.frame).height > 10_000
        }
        if let display = candidates.first,
           let resolution = snapshot.displayResolutions.first(where: { $0.displayID == display.displayID }) {
            return resolution
        }

        let visibleWindowIDs = currentScreenWindowIDs(on: screen)
        var resolution = SpaceDetectionResolver.displayResolution(
            display: displaySnapshot(for: screen, in: snapshot.displaySnapshots),
            snapshot: resolverSnapshot(from: snapshot),
            visibleWindowIDs: visibleWindowIDs,
            fallbackOrderIndex: nil
        )
        if resolution.screenName == nil {
            resolution.screenName = screen.localizedName
        }
        if resolution.displayID == nil {
            resolution.displayID = Self.displayID(for: screen)
        }
        return resolution
    }

    func notesOverlayDisplaySummaries() -> [NotesOverlayDisplaySummary] {
        NSScreen.screens.map { notesOverlayDisplaySummary(for: $0) }
    }

    func notesOverlayDisplaySummary(for screen: NSScreen) -> NotesOverlayDisplaySummary {
        let resolvedOrderIndex = displayResolution(for: screen).resolvedOrderIndex
        let fallback = NotesOverlayDisplaySummary(
            screenName: screen.localizedName,
            displayID: Self.displayID(for: screen),
            screenMatch: "unmatched",
            source: "all Spaces fallback",
            fallbackUsed: true,
            spaces: store.spaces
        )

        guard let snapshot = lastSnapshot,
              let display = displaySnapshot(for: screen, in: snapshot.displaySnapshots),
              !display.spaces.isEmpty else {
            return fallback
        }

        let canUseMonitorSpaces: Bool
        switch display.screenMatch {
        case "exact-display-uuid":
            canUseMonitorSpaces = true
        case "main":
            canUseMonitorSpaces = Self.isMainScreen(screen)
        default:
            canUseMonitorSpaces = false
        }

        guard canUseMonitorSpaces else {
            return NotesOverlayDisplaySummary(
                screenName: screen.localizedName,
                displayID: Self.displayID(for: screen),
                screenMatch: display.screenMatch,
                source: "all Spaces fallback",
                fallbackUsed: true,
                spaces: store.spaces
            )
        }

        if SpaceDetectionResolver.shouldUseAllSpacesForNotesOverlay(
            display: display,
            snapshotSpaces: snapshot.spaces,
            displaySnapshots: snapshot.displaySnapshots,
            resolvedOrderIndex: resolvedOrderIndex,
            liveScreenCount: NSScreen.screens.count
        ) {
            return NotesOverlayDisplaySummary(
                screenName: display.screenName ?? screen.localizedName,
                displayID: display.displayID ?? Self.displayID(for: screen),
                screenMatch: display.screenMatch,
                source: "all Spaces fallback (stale Dock monitor Spaces)",
                fallbackUsed: true,
                spaces: store.spaces
            )
        }

        let overlaySpaces = display.spaces
            .map { store.space(orderIndex: $0.orderIndex) }
            .sorted { $0.orderIndex < $1.orderIndex }

        return NotesOverlayDisplaySummary(
            screenName: display.screenName ?? screen.localizedName,
            displayID: display.displayID ?? Self.displayID(for: screen),
            screenMatch: display.screenMatch,
            source: "Dock monitor Spaces",
            fallbackUsed: false,
            spaces: overlaySpaces
        )
    }

    private func displayResolutions(dockSnapshot: DockSpaceSnapshot) -> [SpaceDisplayResolution] {
        NSScreen.screens.map { screen in
            var resolution = SpaceDetectionResolver.displayResolution(
                display: displaySnapshot(for: screen, in: dockSnapshot.displaySnapshots),
                snapshot: dockSnapshot.resolverSnapshot,
                visibleWindowIDs: currentScreenWindowIDs(on: screen),
                fallbackOrderIndex: nil
            )
            if resolution.screenName == nil {
                resolution.screenName = screen.localizedName
            }
            if resolution.displayID == nil {
                resolution.displayID = Self.displayID(for: screen)
            }
            return resolution
        }
    }

    private func builtInDisplaySnapshot(for screen: NSScreen, in displays: [DisplaySpaceSnapshot]) -> DisplaySpaceSnapshot? {
        if let screenUUID = Self.displayUUIDString(for: screen),
           let exactUUID = displays.first(where: { display in
               display.displayIdentifier?.caseInsensitiveCompare(screenUUID) == .orderedSame
           }) {
            return exactUUID
        }
        if Self.isMainScreen(screen),
           let mainDisplay = displays.first(where: { $0.displayIdentifier == "Main" || $0.screenMatch == "main" }) {
            return mainDisplay
        }
        return nil
    }

    private func mainDisplaySnapshot(in displays: [DisplaySpaceSnapshot]) -> DisplaySpaceSnapshot? {
        displays.first { $0.displayIdentifier == "Main" || $0.screenMatch == "main" }
    }

    private func displaySnapshot(for screen: NSScreen, in displays: [DisplaySpaceSnapshot]) -> DisplaySpaceSnapshot? {
        if let screenUUID = Self.displayUUIDString(for: screen),
           let exactUUID = displays.first(where: { display in
               display.displayIdentifier?.caseInsensitiveCompare(screenUUID) == .orderedSame
           }) {
            return exactUUID
        }
        if let displayID = Self.displayID(for: screen),
           let exactDisplay = displays.first(where: { $0.displayID == displayID && $0.screenMatch == "exact-display-uuid" }) {
            return exactDisplay
        }
        if let displayID = Self.displayID(for: screen),
           let exact = displays.first(where: { $0.displayID == displayID }) {
            return exact
        }
        return displays.first { display in
            guard let frame = display.frame else { return false }
            return frame.intersection(screen.frame).width * frame.intersection(screen.frame).height > 10_000
        }
    }

    private func fallbackSpaces() -> [DetectedSpace] {
        store.spaces.map { DetectedSpace(stableID: $0.stableID, orderIndex: $0.orderIndex) }
    }

    private func resolverSnapshot(from snapshot: SpaceDetectionSnapshot) -> SpaceDetectionResolver.DockSnapshot {
        SpaceDetectionResolver.DockSnapshot(
            spaces: snapshot.spaces,
            currentStableID: snapshot.diagnostics.dockCurrentStableID,
            spaceWindowIDs: readSpaceWindowIDsFromPreferences()
        )
    }

    private func readDockSpaces() -> DockSpaceSnapshot {
        guard let dict = readSpacesPreferenceDomain(),
              let spacesDisplayConfiguration = dict["SpacesDisplayConfiguration"] as? [String: Any],
              let managementData = spacesDisplayConfiguration["Management Data"] as? [String: Any],
              let monitors = managementData["Monitors"] as? [[String: Any]] else {
            return DockSpaceSnapshot(spaces: [], displaySnapshots: [], currentStableID: nil, currentStableIDs: [], monitorCount: 0, spaceWindowIDs: [:])
        }

        var detectedSpaces: [DetectedSpace] = []
        var seen = Set<String>()
        var currentStableID: String?
        var currentStableIDs: [String] = []
        var displaySnapshots: [DisplaySpaceSnapshot] = []
        for (monitorIndex, monitor) in monitors.enumerated() {
            let displayIdentifier = monitor["Display Identifier"] as? String
            let currentID = Self.spaceStableID(from: monitor["Current Space"] as? [String: Any])
            if let currentID {
                currentStableIDs.append(currentID)
                if currentStableID == nil {
                    currentStableID = currentID
                }
            }

            var monitorSpaces: [DetectedSpace] = []
            let rawSpaces = monitor["Spaces"] as? [[String: Any]] ?? []
            guard !rawSpaces.isEmpty || currentID != nil else {
                continue
            }
            for space in rawSpaces {
                guard let id = Self.spaceStableID(from: space), !seen.contains(id) else {
                    continue
                }
                seen.insert(id)
                let detected = DetectedSpace(stableID: id, orderIndex: seen.count)
                detectedSpaces.append(detected)
                monitorSpaces.append(detected)
            }

            let screenMatch = Self.screenMatch(forDisplayIdentifier: displayIdentifier, monitorIndex: monitorIndex)
            let screen = screenMatch.screen
            let activeOrderIndex = currentID.flatMap { id in
                monitorSpaces.first { $0.stableID == id }?.orderIndex
                    ?? detectedSpaces.first { $0.stableID == id }?.orderIndex
            }
            displaySnapshots.append(
                DisplaySpaceSnapshot(
                    displayIdentifier: displayIdentifier,
                    displayID: screen.flatMap(Self.displayID(for:)),
                    screenName: screen?.localizedName,
                    frame: screen?.frame,
                    screenMatch: screenMatch.confidence,
                    spaces: monitorSpaces,
                    currentStableID: currentID,
                    activeOrderIndex: activeOrderIndex,
                    source: activeOrderIndex == nil ? "Dock monitor record" : "Dock monitor Current Space UUID"
                )
            )
        }

        let spaceWindowIDs = readSpaceWindowIDs(from: spacesDisplayConfiguration)
        return DockSpaceSnapshot(
            spaces: detectedSpaces,
            displaySnapshots: displaySnapshots,
            currentStableID: currentStableID,
            currentStableIDs: Self.uniqued(currentStableIDs),
            monitorCount: monitors.count,
            spaceWindowIDs: spaceWindowIDs
        )
    }

    private func readSpaceWindowIDsFromPreferences() -> [String: Set<Int>] {
        guard let dict = readSpacesPreferenceDomain(),
              let spacesDisplayConfiguration = dict["SpacesDisplayConfiguration"] as? [String: Any] else {
            return [:]
        }
        return readSpaceWindowIDs(from: spacesDisplayConfiguration)
    }

    private func readSpaceWindowIDs(from spacesDisplayConfiguration: [String: Any]) -> [String: Set<Int>] {
        guard let properties = spacesDisplayConfiguration["Space Properties"] as? [[String: Any]] else {
            return [:]
        }

        var result: [String: Set<Int>] = [:]
        for property in properties {
            guard let id = property["name"] as? String,
                  let rawWindows = property["windows"] as? [Any] else {
                continue
            }
            let windows = Set(rawWindows.compactMap(Self.intValue))
            if !windows.isEmpty {
                result[id] = windows
            }
        }
        return result
    }

    private func readSpacesPreferenceDomain() -> [String: Any]? {
        let appID = "com.apple.spaces" as CFString
        CFPreferencesAppSynchronize(appID)
        if let keys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [CFString],
           let values = CFPreferencesCopyMultiple(keys as CFArray, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any],
           !values.isEmpty {
            return values
        }

        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")

        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dict = plist as? [String: Any] {
            return dict
        }

        let defaults = UserDefaults(suiteName: "com.apple.spaces")
        defaults?.synchronize()
        return defaults?.persistentDomain(forName: "com.apple.spaces")
    }

    private func currentScreenWindowIDs() -> Set<Int> {
        currentScreenWindowIDs(on: nil)
    }

    private func currentScreenWindowIDs(on screen: NSScreen?) -> Set<Int> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let screenFrames = screen.map { [$0.frame] } ?? NSScreen.screens.map(\.frame)
        return Set(windowInfo.compactMap { info in
            guard let layer = Self.intValue(info[kCGWindowLayer as String]), layer == 0,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  !["Dock", "Window Server", "SystemUIServer"].contains(owner),
                  let windowID = Self.intValue(info[kCGWindowNumber as String]),
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  screenFrames.contains(where: { $0.intersection(bounds).width * $0.intersection(bounds).height > 10_000 }) else {
                return nil
            }
            return windowID
        })
    }

    private func inferActiveSpace(maxCount: Int) -> Int? {
        guard maxCount > 0 else { return nil }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return store.config.lastKnownActiveOrderIndex
        }

        let titles = windowInfo.compactMap { info -> String? in
            if let title = info[kCGWindowName as String] as? String, !title.isEmpty {
                return title
            }
            if let owner = info[kCGWindowOwnerName as String] as? String, owner == "Dock" {
                return info.description
            }
            return nil
        }

        for title in titles {
            if let match = Self.desktopRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title),
               let number = Int(title[range]),
               (1...maxCount).contains(number) {
                return number
            }
        }

        return store.config.lastKnownActiveOrderIndex
    }

    private static let desktopRegex = try! NSRegularExpression(pattern: #"(?i)(?:desktop|space)\s+(\d+)"#)

    private static func spaceStableID(from dictionary: [String: Any]?) -> String? {
        guard let dictionary else { return nil }
        if let uuid = dictionary["uuid"] as? String, !uuid.isEmpty {
            return uuid
        }
        return dictionary["id64"].map { String(describing: $0) }
    }

    private static func screenMatch(forDisplayIdentifier identifier: String?, monitorIndex: Int) -> (screen: NSScreen?, confidence: String) {
        let screens = NSScreen.screens
        if identifier == "Main" {
            return (NSScreen.main ?? screens.first, "main")
        }
        if let identifier,
           let matched = screens.first(where: { screen in
               displayUUIDString(for: screen)?.caseInsensitiveCompare(identifier) == .orderedSame
           }) {
            return (matched, "exact-display-uuid")
        }
        if screens.indices.contains(monitorIndex) {
            return (screens[monitorIndex], "index-fallback")
        }
        return (nil, "unmatched")
    }

    private static func builtInDisplayScreen() -> NSScreen? {
        NSScreen.screens.first {
            $0.localizedName.localizedCaseInsensitiveContains("built-in")
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func isMainScreen(_ screen: NSScreen) -> Bool {
        guard let main = NSScreen.main else { return false }
        return displayID(for: screen) == displayID(for: main)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func displayUUIDString(for screen: NSScreen) -> String? {
        guard let displayID = displayID(for: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private static func displayResolutionSummary(_ resolutions: [SpaceDisplayResolution]) -> [String] {
        resolutions.map { resolution in
            "\(resolution.dockDisplayIdentifier ?? "unknown"):\(resolution.displayID.map(String.init) ?? "unmatched"):\(resolution.resolvedOrderIndex.map(String.init) ?? "none"):\(resolution.source)"
        }
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func detectionDiagnostics(
        dockSnapshot: DockSpaceSnapshot,
        dockActive: Int?,
        windowMatch: SpaceDetectionResolver.WindowMatchResult,
        visibleWindowIDCount: Int,
        active: Int?,
        source: String
    ) -> SpaceDetectionDiagnostics {
        var notes: [String] = []
        if dockSnapshot.spaces.isEmpty {
            notes.append("Dock Spaces preferences were unavailable; using saved order fallback.")
        }
        if dockSnapshot.displaySnapshots.count > 1 {
            notes.append("Multiple live monitor Space records detected; each display can report its own active desktop.")
        }
        if dockSnapshot.currentStableID == nil, !dockSnapshot.spaces.isEmpty {
            notes.append("Dock Spaces were readable, but no Current Space UUID was present.")
        }
        if !dockSnapshot.currentStableIDs.isEmpty && Set(dockSnapshot.currentStableIDs).count > 1 {
            notes.append("Dock reported different Current Space UUIDs across displays; screen-aware labels use the matching display record.")
        }
        if !dockSnapshot.spaceWindowIDs.isEmpty && windowMatch.orderIndex == nil && !windowMatch.candidates.isEmpty {
            notes.append("Visible-window matching was ambiguous; keeping the Dock Current Space or saved fallback.")
        }
        if visibleWindowIDCount == 0 {
            notes.append("No eligible on-screen app windows were available for CGWindow matching.")
        }
        if active == nil {
            notes.append("No active Space could be inferred from public APIs.")
        }

        let confidence: DetectionConfidence
        if dockActive != nil {
            confidence = .high
        } else if windowMatch.orderIndex != nil {
            confidence = .medium
        } else if source == "manual/order fallback" {
            confidence = .fallback
        } else {
            confidence = .low
        }

        return SpaceDetectionDiagnostics(
            confidence: confidence,
            dockSpaceCount: dockSnapshot.spaces.count,
            dockMonitorCount: dockSnapshot.monitorCount,
            dockCurrentStableID: dockSnapshot.currentStableID,
            dockCurrentStableIDs: dockSnapshot.currentStableIDs,
            dockActiveOrderIndex: dockActive,
            visibleWindowIDCount: visibleWindowIDCount,
            uniqueVisibleWindowIDCount: windowMatch.uniqueVisibleWindowIDCount,
            ignoredSharedVisibleWindowIDCount: windowMatch.ignoredSharedVisibleWindowIDCount,
            spaceWindowPropertyCount: dockSnapshot.spaceWindowIDs.count,
            windowMatchedOrderIndex: windowMatch.orderIndex,
            windowMatchCandidates: windowMatch.candidates,
            notes: notes
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private struct DockSpaceSnapshot {
        var spaces: [DetectedSpace]
        var displaySnapshots: [DisplaySpaceSnapshot]
        var currentStableID: String?
        var currentStableIDs: [String]
        var monitorCount: Int
        var spaceWindowIDs: [String: Set<Int>]

        var resolverSnapshot: SpaceDetectionResolver.DockSnapshot {
            SpaceDetectionResolver.DockSnapshot(
                spaces: spaces,
                currentStableID: currentStableID,
                spaceWindowIDs: spaceWindowIDs
            )
        }
    }
}
