import AppKit
import Foundation

@MainActor
final class DiagnosticsService {
    private let store: SpaceStore
    private let detector: SpaceDetector
    private let scanner: WindowScanner
    private let bridge: NativeBridge
    private let screenshotService: ScreenshotService
    private let previewService: SpacePreviewService
    private let loginItemController: LoginItemController
    private let ruleEngine: RuleEngine

    init(
        store: SpaceStore,
        detector: SpaceDetector,
        scanner: WindowScanner,
        bridge: NativeBridge,
        screenshotService: ScreenshotService,
        previewService: SpacePreviewService,
        loginItemController: LoginItemController,
        ruleEngine: RuleEngine
    ) {
        self.store = store
        self.detector = detector
        self.scanner = scanner
        self.bridge = bridge
        self.screenshotService = screenshotService
        self.previewService = previewService
        self.loginItemController = loginItemController
        self.ruleEngine = ruleEngine
    }

    func exportDiagnostics() throws -> URL {
        let directory = diagnosticsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = Self.fileTimestamp.string(from: Date())
        let url = directory.appendingPathComponent("spacesultimate-diagnostics-\(stamp).json")
        let data = try JSONSerialization.data(
            withJSONObject: diagnosticsPayload(),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
        AppLog.shared.info("Exported diagnostics: \(url.path)")
        return url
    }

    func exportGroundTruthTimeline() async throws -> URL {
        let directory = diagnosticsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = Self.fileTimestamp.string(from: Date())
        let url = directory.appendingPathComponent("spacesultimate-ground-truth-\(stamp).json")
        let intervals: [(String, UInt64)] = [
            ("0ms", 0),
            ("250ms", 250_000_000),
            ("900ms", 650_000_000),
            ("1500ms", 600_000_000)
        ]
        var samples: [[String: Any]] = []
        for interval in intervals {
            if interval.1 > 0 {
                try? await Task.sleep(nanoseconds: interval.1)
            }
            detector.refresh(reason: "ground truth recorder \(interval.0)")
            samples.append(groundTruthPayload(sampleLabel: interval.0))
        }

        let payload: [String: Any] = [
            "generatedAt": Self.isoTimestamp.string(from: Date()),
            "sampleCount": samples.count,
            "samples": samples
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
        AppLog.shared.info("Exported ground truth timeline: \(url.path)")
        return url
    }

    func diagnosticsPayload() -> [String: Any] {
        [
            "generatedAt": Self.isoTimestamp.string(from: Date()),
            "app": appPayload(),
            "paths": [
                "config": store.configURL.path,
                "backupsDirectory": store.backupsDirectory.path,
                "invalidConfigDirectory": store.invalidConfigDirectory.path,
                "diagnosticsDirectory": diagnosticsDirectory.path,
                "screenshotsDirectory": screenshotService.screenshotsDirectory.path,
                "previewsDirectory": previewService.previewsDirectory.path
            ],
            "activeSpace": store.config.lastKnownActiveOrderIndex,
            "configBackups": store.listBackups().map { ["file": $0.lastPathComponent, "path": $0.path] },
            "invalidConfigs": store.listInvalidConfigs().map { ["file": $0.lastPathComponent, "path": $0.path] },
            "detection": detectionPayload(),
            "groundTruth": groundTruthPayload(sampleLabel: "diagnostics"),
            "accessibilityTrusted": scanner.isAccessibilityTrusted,
            "screenCaptureTrusted": screenshotService.isScreenCaptureTrusted,
            "lastSwitchAttempt": bridge.lastSwitchAttempt,
            "loginItem": DiagnosticsPayload.loginItem(loginItemController.state),
            "rules": DiagnosticsPayload.rules(ruleEngine.snapshot()),
            "previews": previewService.previewPayload(),
            "settings": settingsPayload(store.config.settings),
            "spaces": store.spaces.map(DiagnosticsPayload.space),
            "spaceNameBindings": store.nameBindingSummaries().map(DiagnosticsPayload.nameBinding),
            "visibleWindows": scanner.scanVisibleWindows().prefix(60).map(windowPayload),
            "recentLogs": Array(AppLog.shared.recentMessages.suffix(200))
        ]
    }

    func groundTruthPayload(sampleLabel: String = "live") -> [String: Any] {
        [
            "sample": sampleLabel,
            "generatedAt": Self.isoTimestamp.string(from: Date()),
            "activeSpace": store.config.lastKnownActiveOrderIndex,
            "screens": screenPayload(),
            "dockSpaces": readDockSpacesPayload(),
            "detection": detectionPayload(),
            "displayMatrix": displayMatrixPayload(),
            "visibleWindows": scanner.scanVisibleWindows().prefix(80).map(windowPayload)
        ]
    }

    var diagnosticsDirectory: URL {
        store.configURL
            .deletingLastPathComponent()
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    var isScreenCaptureTrusted: Bool {
        screenshotService.isScreenCaptureTrusted
    }

    private func appPayload() -> [String: Any] {
        AppIdentity.payload()
    }

    private func settingsPayload(_ settings: AppSettings) -> [String: Any] {
        settings.diagnosticPayload(defaultScreenshotsDirectory: screenshotService.defaultScreenshotsDirectory)
    }

    private func windowPayload(_ window: ScannedWindow) -> [String: Any] {
        [
            "app": window.appName,
            "title": window.title,
            "screen": window.screenName,
            "bounds": [
                "x": window.bounds.origin.x,
                "y": window.bounds.origin.y,
                "width": window.bounds.width,
                "height": window.bounds.height
            ]
        ]
    }

    private func detectionPayload() -> [String: Any] {
        guard let snapshot = detector.lastSnapshot else {
            return [
                "source": "none",
                "event": "no detection snapshot yet",
                "date": NSNull(),
                "activeOrderIndex": NSNull(),
                "spaceCount": store.spaces.count
            ]
        }

        return [
            "source": snapshot.source,
            "event": snapshot.eventDescription,
            "date": Self.isoTimestamp.string(from: snapshot.date),
            "activeOrderIndex": snapshot.activeOrderIndex ?? NSNull(),
            "spaceCount": snapshot.spaces.count,
            "displays": snapshot.displaySnapshots.map(displayDetectionPayload),
            "displayResolutions": snapshot.displayResolutions.map(displayResolutionPayload),
            "details": DiagnosticsPayload.detectionDetails(snapshot.diagnostics)
        ]
    }

    private func displayDetectionPayload(_ display: DisplaySpaceSnapshot) -> [String: Any] {
        [
            "displayIdentifier": display.displayIdentifier ?? NSNull(),
            "displayID": display.displayID.map { Int($0) } ?? NSNull(),
            "screenName": display.screenName ?? NSNull(),
            "screenMatch": display.screenMatch,
            "frame": display.frame.map { frame in
                [
                    "x": frame.origin.x,
                    "y": frame.origin.y,
                    "width": frame.width,
                    "height": frame.height
                ]
            } ?? NSNull(),
            "currentStableID": display.currentStableID ?? NSNull(),
            "activeOrderIndex": display.activeOrderIndex ?? NSNull(),
            "source": display.source,
            "spaces": display.spaces.map { space in
                [
                    "stableID": space.stableID as Any? ?? NSNull(),
                    "orderIndex": space.orderIndex
                ]
            }
        ]
    }

    private func displayResolutionPayload(_ resolution: SpaceDisplayResolution) -> [String: Any] {
        [
            "screenName": resolution.screenName ?? NSNull(),
            "displayID": resolution.displayID.map { Int($0) } ?? NSNull(),
            "dockDisplayIdentifier": resolution.dockDisplayIdentifier ?? NSNull(),
            "screenMatch": resolution.screenMatch,
            "resolvedOrderIndex": resolution.resolvedOrderIndex ?? NSNull(),
            "resolvedDesktopLabel": resolution.resolvedOrderIndex.map { "Desktop \($0)" } ?? NSNull(),
            "fullscreenAppName": resolution.fullscreenSpace?.displayName ?? NSNull(),
            "fullscreenStableID": resolution.fullscreenSpace?.stableID ?? NSNull(),
            "resolvedName": resolution.fullscreenSpace?.displayName ?? resolution.resolvedOrderIndex.map { store.space(orderIndex: $0).displayName } ?? NSNull(),
            "source": resolution.source,
            "confidence": resolution.confidence.rawValue,
            "visibleWindowIDCount": resolution.visibleWindowIDCount,
            "uniqueVisibleWindowIDCount": resolution.uniqueVisibleWindowIDCount,
            "ignoredSharedVisibleWindowIDCount": resolution.ignoredSharedVisibleWindowIDCount,
            "dockCurrentStableID": resolution.dockCurrentStableID ?? NSNull(),
            "dockResolvedOrderIndex": resolution.dockResolvedOrderIndex ?? NSNull(),
            "windowMatchedOrderIndex": resolution.windowMatchedOrderIndex ?? NSNull(),
            "windowMatchCandidates": resolution.windowMatchCandidates.map(DiagnosticsPayload.windowMatch)
        ]
    }

    private func screenPayload() -> [[String: Any]] {
        NSScreen.screens.enumerated().map { index, screen in
            [
                "index": index,
                "name": screen.localizedName,
                "isMain": screen == NSScreen.main,
                "displayID": Self.displayID(for: screen).map { Int($0) } ?? NSNull(),
                "displayUUID": Self.displayUUIDString(for: screen) ?? NSNull(),
                "frame": rectPayload(screen.frame),
                "visibleFrame": rectPayload(screen.visibleFrame)
            ]
        }
    }

    private func displayMatrixPayload() -> [[String: Any]] {
        guard let snapshot = detector.lastSnapshot else { return [] }
        return snapshot.displayResolutions.map { resolution in
            let activeSpace = resolution.resolvedOrderIndex.map { store.space(orderIndex: $0) }
            return [
                "screenName": resolution.screenName ?? NSNull(),
                "displayID": resolution.displayID.map { Int($0) } ?? NSNull(),
                "dockDisplayIdentifier": resolution.dockDisplayIdentifier ?? NSNull(),
                "screenMatch": resolution.screenMatch,
                "dockCurrentStableID": resolution.dockCurrentStableID ?? NSNull(),
                "dockResolvedDesktop": resolution.dockResolvedOrderIndex ?? NSNull(),
                "windowMatchedDesktop": resolution.windowMatchedOrderIndex ?? NSNull(),
                "resolvedDesktop": resolution.resolvedOrderIndex ?? NSNull(),
                "resolvedName": activeSpace?.displayName ?? NSNull(),
                "uiTarget": resolution.resolvedOrderIndex.map { "Desktop \($0)" } ?? NSNull(),
                "source": resolution.source,
                "confidence": resolution.confidence.rawValue,
                "visibleWindowIDCount": resolution.visibleWindowIDCount,
                "windowMatchCandidates": resolution.windowMatchCandidates.map(DiagnosticsPayload.windowMatch)
            ]
        }
    }

    private func readDockSpacesPayload() -> [String: Any] {
        guard let domain = Self.readSpacesPreferenceDomain(),
              let spacesDisplayConfiguration = domain["SpacesDisplayConfiguration"] as? [String: Any],
              let managementData = spacesDisplayConfiguration["Management Data"] as? [String: Any],
              let monitors = managementData["Monitors"] as? [[String: Any]] else {
            return [
                "available": false,
                "reason": "com.apple.spaces SpacesDisplayConfiguration unavailable"
            ]
        }

        let spaceProperties = spacesDisplayConfiguration["Space Properties"] as? [[String: Any]] ?? []
        return [
            "available": true,
            "monitorCount": monitors.count,
            "monitors": monitors.enumerated().map { index, monitor in
                [
                    "index": index,
                    "displayIdentifier": monitor["Display Identifier"] ?? NSNull(),
                    "currentSpace": spaceRecordPayload(monitor["Current Space"] as? [String: Any]),
                    "collapsedSpace": spaceRecordPayload(monitor["Collapsed Space"] as? [String: Any]),
                    "spaces": (monitor["Spaces"] as? [[String: Any]] ?? []).map(spaceRecordPayload)
                ]
            },
            "spaceProperties": spaceProperties.map { property in
                [
                    "name": property["name"] ?? NSNull(),
                    "windowCount": (property["windows"] as? [Any])?.count ?? 0,
                    "windows": property["windows"] ?? []
                ]
            }
        ]
    }

    private func spaceRecordPayload(_ record: [String: Any]?) -> [String: Any] {
        guard let record else {
            return [
                "available": false
            ]
        }
        return [
            "available": true,
            "uuid": record["uuid"] ?? NSNull(),
            "id64": record["id64"] ?? NSNull(),
            "type": record["type"] ?? NSNull(),
            "managedSpaceID": record["ManagedSpaceID"] ?? NSNull()
        ]
    }

    private func rectPayload(_ rect: CGRect) -> [String: Any] {
        [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.width,
            "height": rect.height
        ]
    }

    private static let isoTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func readSpacesPreferenceDomain() -> [String: Any]? {
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
}
