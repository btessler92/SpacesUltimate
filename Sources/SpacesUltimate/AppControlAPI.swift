@preconcurrency import Network
import AppKit
import Foundation

@MainActor
final class AppControlAPI {
    private let store: SpaceStore
    private let detector: SpaceDetector
    private let scanner: WindowScanner
    private let bridge: NativeBridge
    private let appLaunchService: AppLaunchService
    private let screenshotService: ScreenshotService
    private let previewService: SpacePreviewService
    private let loginItemController: LoginItemController
    private let ruleEngine: RuleEngine
    private let diagnosticsService: DiagnosticsService
    private let showHUD: (SpaceMetadata) -> Void
    private let showOverview: () -> Void
    private let showLabelOverlay: () -> Void
    private let hideLabelOverlay: () -> Void
    private let toggleLabelOverlay: () -> Void
    private let notesOverlayStatus: () -> [String: Any]
    private let hideOverview: () -> Void
    private let toggleOverview: () -> Void
    private let showEditor: () -> Void
    private let showPreferences: () -> Void
    private let showDebug: () -> Void
    private var listener: NWListener?
    private(set) var port: UInt16 = 37655
    private let host = "127.0.0.1"

    init(
        store: SpaceStore,
        detector: SpaceDetector,
        scanner: WindowScanner,
        bridge: NativeBridge,
        appLaunchService: AppLaunchService,
        screenshotService: ScreenshotService,
        previewService: SpacePreviewService,
        loginItemController: LoginItemController,
        ruleEngine: RuleEngine,
        diagnosticsService: DiagnosticsService,
        showHUD: @escaping (SpaceMetadata) -> Void,
        showOverview: @escaping () -> Void,
        showLabelOverlay: @escaping () -> Void,
        hideLabelOverlay: @escaping () -> Void,
        toggleLabelOverlay: @escaping () -> Void,
        notesOverlayStatus: @escaping () -> [String: Any],
        hideOverview: @escaping () -> Void,
        toggleOverview: @escaping () -> Void,
        showEditor: @escaping () -> Void,
        showPreferences: @escaping () -> Void,
        showDebug: @escaping () -> Void
    ) {
        self.store = store
        self.detector = detector
        self.scanner = scanner
        self.bridge = bridge
        self.appLaunchService = appLaunchService
        self.screenshotService = screenshotService
        self.previewService = previewService
        self.loginItemController = loginItemController
        self.ruleEngine = ruleEngine
        self.diagnosticsService = diagnosticsService
        self.showHUD = showHUD
        self.showOverview = showOverview
        self.showLabelOverlay = showLabelOverlay
        self.hideLabelOverlay = hideLabelOverlay
        self.toggleLabelOverlay = toggleLabelOverlay
        self.notesOverlayStatus = notesOverlayStatus
        self.hideOverview = hideOverview
        self.toggleOverview = toggleOverview
        self.showEditor = showEditor
        self.showPreferences = showPreferences
        self.showDebug = showDebug
    }

    func start() {
        guard listener == nil else { return }
        do {
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                AppLog.shared.error("Control API failed to start: invalid port \(port)")
                return
            }
            let listener = try NWListener(using: Self.listenerParameters(port: endpointPort))
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handle(connection: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    AppLog.shared.info("Control API state: \(String(describing: state))")
                    if case .failed = state {
                        self?.listener?.cancel()
                        self?.listener = nil
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            AppLog.shared.info("Control API listening on http://\(host):\(port)")
        } catch {
            AppLog.shared.error("Control API failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    static func listenerParameters(port: NWEndpoint.Port) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        return parameters
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    AppLog.shared.warning("Control API receive failed: \(error.localizedDescription)")
                    connection.cancel()
                    return
                }
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let response = self.route(request)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func route(_ request: String) -> Data {
        guard ControlAPIRequestPolicy.allows(request, port: port) else {
            return response(status: "403 Forbidden", body: ["error": "Only local command-line requests are accepted"])
        }
        guard let firstLine = request.split(separator: "\r\n", omittingEmptySubsequences: false).first else {
            return response(status: "400 Bad Request", body: ["error": "empty request"])
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return response(status: "400 Bad Request", body: ["error": "invalid request line"])
        }

        let target = String(parts[1])
        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else {
            return response(status: "400 Bad Request", body: ["error": "invalid url"])
        }

        switch components.path {
        case "/status":
            return response(body: statusPayload())
        case "/refresh":
            detector.refresh(reason: "control api")
            return response(body: statusPayload(extra: ["ok": true]))
        case "/hud":
            let space = requestedSpace(components) ?? store.space(orderIndex: store.config.lastKnownActiveOrderIndex)
            showHUD(space)
            return response(body: ["ok": true, "shown": DiagnosticsPayload.space(space)])
        case "/overview/show":
            showOverview()
            return response(body: ["ok": true, "overview": "shown"])
        case "/labels/show", "/overlay/show":
            showLabelOverlay()
            return response(body: ["ok": true, "labels": "shown"])
        case "/labels/hide", "/overlay/hide":
            hideLabelOverlay()
            return response(body: ["ok": true, "labels": "hidden"])
        case "/labels/toggle", "/overlay/toggle":
            toggleLabelOverlay()
            return response(body: ["ok": true, "labels": "toggled"])
        case "/labels/status", "/overlay/status":
            return response(body: notesOverlayStatus())
        case "/overview/hide":
            hideOverview()
            return response(body: ["ok": true, "overview": "hidden"])
        case "/overview/toggle":
            toggleOverview()
            return response(body: ["ok": true, "overview": "toggled"])
        case "/editor/show":
            showEditor()
            return response(body: ["ok": true, "editor": "shown"])
        case "/preferences/show":
            showPreferences()
            return response(body: ["ok": true, "preferences": "shown"])
        case "/debug/show":
            showDebug()
            return response(body: ["ok": true, "debug": "shown"])
        case "/settings/update":
            let settings = applySettingsUpdate(components)
            store.updateSettings(settings)
            if !settings.apiEnabled {
                DispatchQueue.main.async { [weak self] in self?.stop() }
            }
            return response(body: ["ok": true, "settings": settingsPayload(settings)])
        case "/settings/defaults":
            return response(body: preferenceDefaultsPayload())
        case "/onboarding/reset":
            var settings = store.config.settings
            settings.onboardingCompleted = false
            store.updateSettings(settings)
            return response(body: ["ok": true, "settings": settingsPayload(settings)])
        case "/onboarding/complete":
            var settings = store.config.settings
            settings.onboardingCompleted = true
            store.updateSettings(settings)
            return response(body: ["ok": true, "settings": settingsPayload(settings)])
        case "/config/update":
            guard var space = requestedSpace(components) else {
                return response(status: "400 Bad Request", body: ["error": "missing or invalid space"])
            }
            applyConfigUpdate(to: &space, components: components)
            store.update(space)
            return response(body: ["ok": true, "updated": DiagnosticsPayload.space(space)])
        case "/config/reset":
            store.resetNames()
            return response(body: statusPayload(extra: ["ok": true, "reset": true]))
        case "/config/backups":
            return response(body: ["ok": true, "backups": backupPayload()])
        case "/config/invalid":
            return response(body: ["ok": true, "invalidConfigs": invalidConfigPayload()])
        case "/config/backup":
            let url = store.createBackup(reason: "manual-api")
            return response(body: ["ok": url != nil, "file": url?.path ?? NSNull(), "backups": backupPayload()])
        case "/config/restore-latest":
            do {
                try store.restoreLatestBackup()
                return response(body: statusPayload(extra: ["ok": true, "restored": true, "backups": backupPayload()]))
            } catch {
                return response(status: "500 Internal Server Error", body: ["ok": false, "error": error.localizedDescription, "backups": backupPayload()])
            }
        case "/config/name-bindings":
            return response(body: ["ok": true, "bindings": store.nameBindingSummaries().map(DiagnosticsPayload.nameBinding)])
        case "/config/repair-names":
            let repaired = store.repairOrderFallbackNamesFromHistory()
            return response(body: [
                "ok": true,
                "repaired": repaired.map { ["space": $0.key, "name": $0.value] }.sorted { ($0["space"] as? Int ?? 0) < ($1["space"] as? Int ?? 0) },
                "bindings": store.nameBindingSummaries().map(DiagnosticsPayload.nameBinding),
                "spaces": store.spaces.map(DiagnosticsPayload.space)
            ])
        case "/permissions/accessibility":
            scanner.requestAccessibilityIfNeeded()
            return response(body: ["ok": true, "accessibilityTrusted": scanner.isAccessibilityTrusted])
        case "/permissions/screen-capture":
            let trusted = screenshotService.requestScreenCaptureIfNeeded()
            return response(body: ["ok": trusted, "screenCaptureTrusted": screenshotService.isScreenCaptureTrusted])
        case "/login-item/status":
            return response(body: ["ok": true, "loginItem": DiagnosticsPayload.loginItem(loginItemController.state)])
        case "/rules/suggestions":
            return response(body: ["ok": true, "rules": DiagnosticsPayload.rules(ruleEngine.snapshot())])
        case "/previews/capture":
            let space = requestedSpace(components) ?? store.space(orderIndex: store.config.lastKnownActiveOrderIndex)
            previewService.capturePreview(for: space)
            return response(body: [
                "ok": previewService.existingPreviewURL(for: space) != nil,
                "space": DiagnosticsPayload.space(space),
                "file": previewService.existingPreviewURL(for: space)?.path ?? NSNull(),
                "screenCaptureTrusted": previewService.isScreenCaptureTrusted
            ])
        case "/previews/status":
            return response(body: [
                "ok": true,
                "directory": previewService.previewsDirectory.path,
                "screenCaptureTrusted": previewService.isScreenCaptureTrusted,
                "previews": previewService.previewPayload()
            ])
        case "/rules/assign-visible":
            let space = requestedSpace(components) ?? store.space(orderIndex: store.config.lastKnownActiveOrderIndex)
            let added = ruleEngine.assignUnassignedVisibleApps(to: space.orderIndex)
            return response(body: [
                "ok": true,
                "space": space.orderIndex,
                "addedApps": added,
                "updated": DiagnosticsPayload.space(store.space(orderIndex: space.orderIndex)),
                "rules": DiagnosticsPayload.rules(ruleEngine.snapshot())
            ])
        case "/rules/resolve-duplicates":
            let resolved = ruleEngine.resolveDuplicateAssignments()
            return response(body: [
                "ok": true,
                "resolved": resolved,
                "rules": DiagnosticsPayload.rules(ruleEngine.snapshot()),
                "spaces": store.spaces.map(DiagnosticsPayload.space)
            ])
        case "/login-item/update":
            guard let enabled = components.queryItems?.first(where: { $0.name == "enabled" })?.value.flatMap(Bool.init) else {
                return response(status: "400 Bad Request", body: ["error": "missing enabled=true|false"])
            }
            do {
                try loginItemController.setEnabled(enabled)
                return response(body: ["ok": true, "loginItem": DiagnosticsPayload.loginItem(loginItemController.state)])
            } catch {
                return response(status: "500 Internal Server Error", body: ["ok": false, "error": error.localizedDescription, "loginItem": DiagnosticsPayload.loginItem(loginItemController.state)])
            }
        case "/switch":
            guard let space = requestedSpace(components) else {
                return response(status: "400 Bad Request", body: ["error": "missing or invalid space"])
            }
            let ok = bridge.switchToSpace(space, from: store.config.lastKnownActiveOrderIndex)
            return response(body: ["ok": ok, "attempt": bridge.lastSwitchAttempt])
        case "/apps/launch":
            let space = requestedSpace(components) ?? store.space(orderIndex: store.config.lastKnownActiveOrderIndex)
            let shouldSwitch = components.queryItems?.first(where: { $0.name == "switch" })?.value.flatMap(Bool.init) ?? false
            let switched = shouldSwitch ? bridge.switchToSpace(space, from: store.config.lastKnownActiveOrderIndex) : true
            guard switched else {
                return response(body: [
                    "ok": false,
                    "space": DiagnosticsPayload.space(space),
                    "switched": false,
                    "attempt": bridge.lastSwitchAttempt,
                    "results": []
                ])
            }
            if shouldSwitch && switched {
                Thread.sleep(forTimeInterval: 0.35)
            }
            let results = appLaunchService.launchAssignedApps(for: space)
            return response(body: [
                "ok": results.contains(where: \.launched),
                "space": DiagnosticsPayload.space(space),
                "switched": switched,
                "attempt": bridge.lastSwitchAttempt,
                "results": results.map(appLaunchPayload)
            ])
        case "/screenshot":
            do {
                let urls = try screenshotService.captureScreens()
                return response(body: ["ok": true, "files": urls.map(\.path)])
            } catch {
                return response(status: "500 Internal Server Error", body: ["ok": false, "error": error.localizedDescription])
            }
        case "/diagnostics/export":
            do {
                let url = try diagnosticsService.exportDiagnostics()
                return response(body: ["ok": true, "file": url.path])
            } catch {
                return response(status: "500 Internal Server Error", body: ["ok": false, "error": error.localizedDescription])
            }
        case "/ground-truth":
            return response(body: ["ok": true, "groundTruth": diagnosticsService.groundTruthPayload(sampleLabel: "api")])
        case "/app/quit":
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return response(body: ["ok": true, "app": "terminating"])
        default:
            return response(status: "404 Not Found", body: [
                "error": "unknown endpoint",
                "endpoints": [
                    "/status",
                    "/refresh",
                    "/hud?space=1",
                    "/overview/show",
                    "/overlay/show",
                    "/overlay/hide",
                    "/overlay/toggle",
                    "/overlay/status",
                    "/labels/show",
                    "/labels/hide",
                    "/labels/toggle",
                    "/labels/status",
                    "/overview/hide",
                    "/overview/toggle",
                    "/editor/show",
                    "/preferences/show",
                    "/settings/defaults",
                    "/debug/show",
                    "/settings/update?hudEnabled=true&hudDuration=1.5&apiEnabled=true&globalHotkeyEnabled=false&menuBarDisplayMode=name&menuBarLabelPosition=rightOfCenter&screenshotDirectoryPath=/tmp",
                    "/onboarding/reset",
                    "/onboarding/complete",
                    "/login-item/status",
                    "/login-item/update?enabled=true",
                    "/rules/suggestions",
                    "/previews/capture?space=1",
                    "/previews/status",
                    "/rules/assign-visible?space=1",
                    "/rules/resolve-duplicates",
                    "/config/update?space=1&name=MATLAB&color=%232F80ED&icon=M&note=Analysis",
                    "/config/reset",
                    "/config/backups",
                    "/config/invalid",
                    "/config/backup",
                    "/config/restore-latest",
                    "/config/name-bindings",
                    "/config/repair-names",
                    "/permissions/accessibility",
                    "/permissions/screen-capture",
                    "/switch?space=1",
                    "/apps/launch?space=1&switch=true",
                    "/screenshot",
                    "/diagnostics/export",
                    "/ground-truth",
                    "/app/quit"
                ]
            ])
        }
    }

    private func applyConfigUpdate(to space: inout SpaceMetadata, components: URLComponents) {
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        if let name = items["name"] {
            space.name = name
        }
        if let color = items["color"], color.hasPrefix("#"), color.count == 7 {
            space.colorHex = color
        }
        if let icon = items["icon"] {
            space.icon = icon
        }
        if let note = items["note"] {
            space.note = note
        }
        if let shortcut = items["shortcut"] {
            space.shortcut = shortcut
        }
        if let apps = items["apps"] {
            space.assignedApps = apps
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    private func applySettingsUpdate(_ components: URLComponents) -> AppSettings {
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        var settings = store.config.settings
        if let hudEnabled = items["hudEnabled"].flatMap(Bool.init) {
            settings.hudEnabled = hudEnabled
        }
        if let duration = items["hudDuration"].flatMap(Double.init) {
            settings.hudDurationSeconds = duration
        }
        if let value = items["hudFadeInSeconds"].flatMap(Double.init) { settings.hudFadeInSeconds = value }
        if let value = items["hudHoldSeconds"].flatMap(Double.init) { settings.hudHoldSeconds = value }
        if let value = items["hudScale"].flatMap(Double.init) { settings.hudScale = value }
        if let value = items["hudBackgroundOpacity"].flatMap(Double.init) { settings.hudBackgroundOpacity = value }
        if let value = items["hudPosition"].flatMap(HUDPosition.init(rawValue:)) { settings.hudPosition = value }
        if let value = items["hudShowsDesktopNumber"].flatMap(Bool.init) { settings.hudShowsDesktopNumber = value }
        if let apiEnabled = items["apiEnabled"].flatMap(Bool.init) {
            settings.apiEnabled = apiEnabled
        }
        if let hotkeyEnabled = items["globalHotkeyEnabled"].flatMap(Bool.init) {
            settings.globalHotkeyEnabled = hotkeyEnabled
        }
        if let globalHotkeyShortcut = items["globalHotkeyShortcut"] {
            settings.globalHotkeyShortcut = globalHotkeyShortcut
        }
        if let notesOverlayHotkeyEnabled = items["notesOverlayHotkeyEnabled"].flatMap(Bool.init) {
            settings.notesOverlayHotkeyEnabled = notesOverlayHotkeyEnabled
        }
        if let notesOverlayHotkeyShortcut = items["notesOverlayHotkeyShortcut"] {
            settings.notesOverlayHotkeyShortcut = notesOverlayHotkeyShortcut
        }
        if let notesOverlayItemOpacity = items["notesOverlayItemOpacity"].flatMap(Double.init) {
            settings.notesOverlayItemOpacity = notesOverlayItemOpacity
        }
        if let notesOverlayBackgroundOpacity = items["notesOverlayBackgroundOpacity"].flatMap(Double.init) {
            settings.notesOverlayBackgroundOpacity = notesOverlayBackgroundOpacity
        }
        if let notesOverlayHeightPixels = items["notesOverlayHeightPixels"].flatMap(Double.init) {
            settings.notesOverlayHeightPixels = notesOverlayHeightPixels
        }
        if let autoLaunchAssignedApps = items["autoLaunchAssignedApps"].flatMap(Bool.init) {
            settings.autoLaunchAssignedApps = autoLaunchAssignedApps
        }
        if let onboardingCompleted = items["onboardingCompleted"].flatMap(Bool.init) {
            settings.onboardingCompleted = onboardingCompleted
        }
        if let screenshotDirectoryPath = items["screenshotDirectoryPath"] {
            settings.screenshotDirectoryPath = screenshotDirectoryPath
        }
        if let rawMode = items["menuBarDisplayMode"], let mode = MenuBarDisplayMode(rawValue: rawMode) {
            settings.menuBarDisplayMode = mode
        }
        if let rawPosition = items["menuBarLabelPosition"], let position = MenuBarLabelPosition(rawValue: rawPosition) {
            settings.menuBarLabelPosition = position
        }
        return settings.normalized
    }

    private func requestedSpace(_ components: URLComponents) -> SpaceMetadata? {
        guard let value = components.queryItems?.first(where: { $0.name == "space" })?.value,
              let index = Int(value),
              store.spaces.contains(where: { $0.orderIndex == index }) else {
            return nil
        }
        return store.space(orderIndex: index)
    }

    private func statusPayload(extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = [
            "app": "SpacesUltimate",
            "appIdentity": AppIdentity.payload(),
            "api": "http://\(host):\(port)",
            "activeSpace": store.config.lastKnownActiveOrderIndex,
            "accessibilityTrusted": scanner.isAccessibilityTrusted,
            "screenCaptureTrusted": screenshotService.isScreenCaptureTrusted,
            "config": store.configURL.path,
            "configBackups": backupPayload(),
            "invalidConfigs": invalidConfigPayload(),
            "detection": detectionPayload(),
            "menuBar": menuBarPayload(MenuBarController.currentStatusSnapshot),
            "notesOverlay": notesOverlayStatus(),
            "groundTruth": diagnosticsService.groundTruthPayload(sampleLabel: "status"),
            "previews": [
                "directory": previewService.previewsDirectory.path,
                "items": previewService.previewPayload()
            ],
            "lastSwitchAttempt": bridge.lastSwitchAttempt,
            "loginItem": DiagnosticsPayload.loginItem(loginItemController.state),
            "rules": DiagnosticsPayload.rules(ruleEngine.snapshot()),
            "settings": settingsPayload(store.config.settings),
            "preferenceDefaults": preferenceDefaultsPayload(),
            "spaces": store.spaces.map(DiagnosticsPayload.space),
            "spaceNameBindings": store.nameBindingSummaries().map(DiagnosticsPayload.nameBinding),
            "visibleWindows": scanner.scanVisibleWindows().prefix(30).map { window in
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
        ]
        extra.forEach { payload[$0.key] = $0.value }
        return payload
    }

    private func preferenceDefaultsPayload() -> [String: Any] {
        let preset = store.preferenceDefaults
        return [
            "source": store.config.savedPreferenceDefaults == nil ? "factory" : "saved",
            "savedAt": preset.savedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "settings": settingsPayload(preset.settings),
            "launchAtLogin": preset.launchAtLogin,
            "currentMatchesDefault": preset.matches(store.config.settings, launchAtLogin: loginItemController.isEnabled),
            "factorySettings": settingsPayload(.defaults),
            "factoryLaunchAtLogin": PreferenceDefaults.factory.launchAtLogin
        ]
    }

    private func settingsPayload(_ settings: AppSettings) -> [String: Any] {
        settings.diagnosticPayload(defaultScreenshotsDirectory: screenshotService.defaultScreenshotsDirectory)
    }

    private func menuBarPayload(_ snapshot: MenuBarStatusSnapshot) -> [String: Any] {
        [
            "autosaveName": snapshot.autosaveName,
            "isVisible": snapshot.isVisible,
            "title": snapshot.title,
            "badgeText": snapshot.badgeText,
            "toolTip": snapshot.toolTip ?? NSNull(),
            "menuItemTitles": snapshot.menuItemTitles,
            "screenCount": snapshot.screenCount,
            "activeScreenName": snapshot.activeScreenName ?? NSNull(),
            "activeDesktopLabel": snapshot.activeDesktopLabel,
            "activeDisplayName": snapshot.activeDisplayName,
            "statusItemLength": snapshot.statusItemLength,
            "isButtonHidden": snapshot.isButtonHidden,
            "buttonAlphaValue": snapshot.buttonAlphaValue,
            "buttonFrameInScreen": snapshot.buttonFrameInScreen.map(rectPayload) ?? NSNull(),
            "buttonWindowFrame": snapshot.buttonWindowFrame.map(rectPayload) ?? NSNull(),
            "buttonWindowIsVisible": snapshot.buttonWindowIsVisible,
            "buttonWindowNumber": snapshot.buttonWindowNumber,
            "buttonWindowLevel": snapshot.buttonWindowLevel,
            "buttonWindowScreenName": snapshot.buttonWindowScreenName ?? NSNull(),
            "buttonWindowOcclusionVisible": snapshot.buttonWindowOcclusionVisible,
            "buttonWindowClassName": snapshot.buttonWindowClassName ?? NSNull(),
            "buttonSuperviewClassName": snapshot.buttonSuperviewClassName ?? NSNull(),
            "resolutionSource": snapshot.resolutionSource,
            "resolutionConfidence": snapshot.resolutionConfidence.rawValue
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

    private func appLaunchPayload(_ result: AppLaunchService.LaunchResult) -> [String: Any] {
        [
            "app": result.appName,
            "launched": result.launched,
            "path": result.path ?? NSNull(),
            "message": result.message
        ]
    }

    private func backupPayload() -> [[String: Any]] {
        store.listBackups().map { url in
            [
                "file": url.lastPathComponent,
                "path": url.path
            ]
        }
    }

    private func invalidConfigPayload() -> [[String: Any]] {
        store.listInvalidConfigs().map { url in
            [
                "file": url.lastPathComponent,
                "path": url.path
            ]
        }
    }

    private func response(status: String = "200 OK", body: [String: Any]) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Content-Length: \(data.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r

        """
        var response = Data(headers.utf8)
        response.append(data)
        return response
    }

    private static let isoTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
