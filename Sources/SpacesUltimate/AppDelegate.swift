import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didStart = false
    private let store = SpaceStore()
    private lazy var detector = SpaceDetector(store: store)
    private let scanner = WindowScanner()
    private let bridge = NativeBridge()
    private let appLaunchService = AppLaunchService()
    private let loginItemController = LoginItemController()
    private lazy var ruleEngine = RuleEngine(store: store, scanner: scanner)
    private lazy var screenshotService = ScreenshotService(store: store)
    private lazy var previewService = SpacePreviewService(store: store)
    private lazy var diagnosticsService = DiagnosticsService(
        store: store,
        detector: detector,
        scanner: scanner,
        bridge: bridge,
        screenshotService: screenshotService,
        previewService: previewService,
        loginItemController: loginItemController,
        ruleEngine: ruleEngine
    )
    private lazy var menuBar = MenuBarController(
        store: store,
        detector: detector,
        openEditor: { [weak self] in self?.showEditor() },
        openOverview: { [weak self] in self?.showOverview() },
        showLabelOverlay: { [weak self] in self?.showLabelOverlay() },
        toggleLabelOverlay: { [weak self] in self?.labelOverlayController.toggleFromMenuBar() },
        openPreferences: { [weak self] in self?.showPreferences() },
        openDebug: { [weak self] in self?.showDebug() },
        refreshSpaces: { [weak self] in self?.refreshSpacesFromMenu() },
        resetMenuBarItem: { [weak self] in self?.resetMenuBarItemFromMenu() }
    )
    private lazy var hudController = HUDController()
    private lazy var labelOverlayController = LabelOverlayController(store: store, detector: detector, bridge: bridge)
    private lazy var missionControlMonitor = MissionControlMonitor { [weak self] active in
        guard let self else { return }
        if active {
            self.labelOverlayController.show(duration: 0, followsMissionControl: true)
        } else {
            self.labelOverlayController.missionControlDidClose()
        }
    }
    private var notesOverlayPresentationFingerprint: NotesOverlayPresentationFingerprint?
    private lazy var overviewController = OverviewController(store: store, scanner: scanner, bridge: bridge, ruleEngine: ruleEngine, previewService: previewService)
    private var preferencesWindow: PreferencesWindowController?
    private lazy var onboardingWindow = OnboardingWindowController(
        store: store,
        scanner: scanner,
        showEditor: { [weak self] in self?.showEditor() },
        showPreferences: { [weak self] in self?.showPreferences() }
    )
    private lazy var editorWindow = SpaceEditorWindowController(
        store: store,
        detector: detector,
        scanner: scanner,
        bridge: bridge,
        appLaunchService: appLaunchService,
        screenshotService: screenshotService,
        previewService: previewService,
        showHUD: { [weak self] space in self?.showHUD(space: space) },
        showOverview: { [weak self] in self?.overviewController.show() },
        showLabelOverlay: { [weak self] in self?.showLabelOverlay() },
        showPreferences: { [weak self] in self?.showPreferences() }
    )
    private var debugWindow: DebugWindowController?
    private lazy var controlAPI = AppControlAPI(
        store: store,
        detector: detector,
        scanner: scanner,
        bridge: bridge,
        appLaunchService: appLaunchService,
        screenshotService: screenshotService,
        previewService: previewService,
        loginItemController: loginItemController,
        ruleEngine: ruleEngine,
        diagnosticsService: diagnosticsService,
        showHUD: { [weak self] space in self?.showHUD(space: space) },
        showOverview: { [weak self] in self?.overviewController.show() },
        showLabelOverlay: { [weak self] in self?.showLabelOverlay() },
        hideLabelOverlay: { [weak self] in self?.labelOverlayController.hide() },
        toggleLabelOverlay: { [weak self] in self?.toggleLabelOverlay() },
        notesOverlayStatus: { [weak self] in
            guard let self else { return ["visible": false, "panelCount": 0, "panels": []] }
            var payload = self.labelOverlayController.statusPayload()
            payload["missionControl"] = self.missionControlMonitor.statusPayload()
            return payload
        },
        hideOverview: { [weak self] in self?.overviewController.hide() },
        toggleOverview: { [weak self] in self?.overviewController.toggle() },
        showEditor: { [weak self] in self?.showEditor() },
        showPreferences: { [weak self] in self?.showPreferences() },
        showDebug: { [weak self] in self?.showDebug() }
    )
    private lazy var hotKey = GlobalHotKeyController { [weak self] in
        self?.showOverview()
    }
    private lazy var notesOverlayHotKey = GlobalHotKeyController(logName: "notes overlay") { [weak self] in
        self?.toggleLabelOverlay()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && !labelOverlayController.isVisible {
            showEditor()
        }
        return true
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        AppLog.shared.info("SpacesUltimate launched")
        menuBar.start()
        labelOverlayController.retainsNotesForAppMousePress = { [weak self] point, button, window in
            guard let self else { return false }
            return self.menuBar.isSettingsMenuInteraction(at: point, mouseButton: button)
                || self.preferencesWindow?.ownsInteraction(in: window, at: point) == true
                || (window?.windowController as? SpaceEditorWindowController)?.isPreferencesInteraction(at: point) == true
        }
        AppLog.shared.info("Menu bar started")
        applyRuntimeSettings()

        notesOverlayPresentationFingerprint = NotesOverlayPresentationFingerprint(config: store.config)
        store.onChange = { [weak self] config in
            guard let self else { return }
            let nextFingerprint = NotesOverlayPresentationFingerprint(config: config)
            let notesOverlayPresentationChanged = nextFingerprint != self.notesOverlayPresentationFingerprint
            self.notesOverlayPresentationFingerprint = nextFingerprint

            self.menuBar.refresh()
            self.overviewController.reload()
            if notesOverlayPresentationChanged {
                self.labelOverlayController.reloadIfVisible()
            }
            self.debugWindow?.reloadIfVisible()
            self.preferencesWindow?.reloadIfVisible()
            self.applyRuntimeSettings()
        }

        detector.onActiveSpaceChanged = { [weak self] snapshot in
            guard let self, let active = snapshot.activeOrderIndex else { return }
            let space = self.store.space(orderIndex: active)
            self.previewService.capturePreview(for: space)
            self.menuBar.refresh()
            if self.store.config.settings.hudEnabled {
                self.hudController.show(store: self.store, detector: self.detector, settings: self.store.config.settings)
            }
            if self.store.config.settings.autoLaunchAssignedApps {
                _ = self.appLaunchService.launchAssignedApps(for: space)
            }
            self.debugWindow?.reloadIfVisible()
        }

        detector.onSnapshot = { [weak self] snapshot in
            self?.menuBar.refresh()
            self?.labelOverlayController.refreshActiveHighlights(reason: snapshot.eventDescription)
            self?.debugWindow?.reloadIfVisible()
        }

        detector.start()
        missionControlMonitor.start()
        showOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        notesOverlayHotKey.unregister()
        missionControlMonitor.stop()
        labelOverlayController.hide()
        hudController.hide()
        controlAPI.stop()
        detector.stop()
    }

    private func showEditor() {
        NSApp.activate(ignoringOtherApps: true)
        editorWindow.showWindow(nil)
    }

    private func showOverview() {
        overviewController.toggle()
    }

    private func showLabelOverlay() {
        labelOverlayController.show(duration: 0)
    }

    private func toggleLabelOverlay() {
        labelOverlayController.toggle(duration: 0)
    }

    private func showHUD(space: SpaceMetadata) {
        guard store.config.settings.hudEnabled else { return }
        hudController.show(space: space, desktopNumber: space.orderIndex, settings: store.config.settings)
    }

    private func showDebug() {
        NSApp.activate(ignoringOtherApps: true)
        let controller = makeDebugWindowIfNeeded()
        controller.showWindow(nil)
    }

    private func showPreferences() {
        // Set retention before activation can cause Mission Control to exit.
        labelOverlayController.keepVisibleForSettings()
        NSApp.activate(ignoringOtherApps: true)
        let controller = makePreferencesWindowIfNeeded()
        controller.showWindow(nil)
    }

    private func showOnboardingIfNeeded() {
        guard !store.config.settings.onboardingCompleted else { return }
        showOnboarding()
    }

    private func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow.showWindow(nil)
    }

    private func refreshSpacesFromMenu() {
        detector.refresh(reason: "menu refresh")
        menuBar.refresh()
    }

    private func resetMenuBarItemFromMenu() {
        MenuBarController.resetPersistedSystemPlacement()
        menuBar.refresh()
        AppLog.shared.info("Reset persisted menu bar status item settings")
    }

    private func applyRuntimeSettings() {
        if store.config.settings.globalHotkeyEnabled {
            hotKey.register(shortcut: store.config.settings.globalHotkeyShortcut)
        } else {
            hotKey.unregister()
            AppLog.shared.info("Global overview hotkey disabled in settings")
        }

        if store.config.settings.notesOverlayHotkeyEnabled {
            notesOverlayHotKey.register(shortcut: store.config.settings.notesOverlayHotkeyShortcut)
        } else {
            notesOverlayHotKey.unregister()
            AppLog.shared.info("Global notes overlay hotkey disabled in settings")
        }

        if store.config.settings.apiEnabled {
            controlAPI.start()
            AppLog.shared.info("Control API enabled in settings")
        } else {
            controlAPI.stop()
            AppLog.shared.info("Control API disabled in settings")
        }
    }

    private func makePreferencesWindowIfNeeded() -> PreferencesWindowController {
        if let preferencesWindow {
            return preferencesWindow
        }
        let controller = PreferencesWindowController(store: store, scanner: scanner,
            screenshotService: screenshotService, loginItemController: loginItemController,
            previewHUD: { [weak self] settings in
                guard let self else { return }
                self.hudController.show(store: self.store, detector: self.detector, settings: settings)
            })
        preferencesWindow = controller
        return controller
    }

    private func makeDebugWindowIfNeeded() -> DebugWindowController {
        if let debugWindow {
            return debugWindow
        }
        let controller = DebugWindowController(
            store: store,
            detector: detector,
            scanner: scanner,
            bridge: bridge,
            ruleEngine: ruleEngine,
            diagnosticsService: diagnosticsService,
            showHUD: { [weak self] in
                guard let self else { return }
                self.showHUD(space: self.store.space(orderIndex: self.store.config.lastKnownActiveOrderIndex))
            },
            showOverview: { [weak self] in self?.overviewController.show() },
            hideOverview: { [weak self] in self?.overviewController.hide() },
            switchActiveSpace: { [weak self] in
                guard let self else { return }
                _ = self.bridge.switchToSpace(
                    self.store.space(orderIndex: self.store.config.lastKnownActiveOrderIndex),
                    from: self.store.config.lastKnownActiveOrderIndex
                )
            }
        )
        debugWindow = controller
        return controller
    }
}
