import AppKit

struct MenuBarStatusSnapshot: Equatable {
    var autosaveName: String
    var isVisible: Bool
    var title: String
    var badgeText: String
    var toolTip: String?
    var menuItemTitles: [String]
    var screenCount: Int
    var activeScreenName: String?
    var activeDesktopLabel: String
    var activeDisplayName: String
    var statusItemLength: CGFloat
    var isButtonHidden: Bool
    var buttonAlphaValue: CGFloat
    var buttonFrameInScreen: CGRect?
    var buttonWindowFrame: CGRect?
    var buttonWindowIsVisible: Bool
    var buttonWindowNumber: Int
    var buttonWindowLevel: Int
    var buttonWindowScreenName: String?
    var buttonWindowOcclusionVisible: Bool
    var buttonWindowClassName: String?
    var buttonSuperviewClassName: String?
    var resolutionSource: String
    var resolutionConfidence: DetectionConfidence

    static let unavailable = MenuBarStatusSnapshot(
        autosaveName: MenuBarStatusItemDefaults.autosaveName,
        isVisible: false,
        title: "",
        badgeText: "",
        toolTip: nil,
        menuItemTitles: [],
        screenCount: 0,
        activeScreenName: nil,
        activeDesktopLabel: "",
        activeDisplayName: "",
        statusItemLength: 0,
        isButtonHidden: true,
        buttonAlphaValue: 0,
        buttonFrameInScreen: nil,
        buttonWindowFrame: nil,
        buttonWindowIsVisible: false,
        buttonWindowNumber: 0,
        buttonWindowLevel: 0,
        buttonWindowScreenName: nil,
        buttonWindowOcclusionVisible: false,
        buttonWindowClassName: nil,
        buttonSuperviewClassName: nil,
        resolutionSource: "unavailable",
        resolutionConfidence: .fallback
    )
}

private struct MenuBarActiveStatus {
    var screen: NSScreen?
    var resolution: SpaceDisplayResolution
    var space: SpaceMetadata?

    var desktopLabel: String {
        space?.desktopLabel ?? "Desktop Unknown"
    }

    var displayName: String {
        space?.displayName ?? "Unknown"
    }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static private(set) var currentStatusSnapshot = MenuBarStatusSnapshot.unavailable

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var isMenuTracking = false
    private var lastMenuItemTitles: [String] = []
    private let store: SpaceStore
    private let detector: SpaceDetector
    private let openEditor: () -> Void
    private let openOverview: () -> Void
    private let showLabelOverlay: () -> Void
    private let toggleLabelOverlay: () -> Void
    private let openPreferences: () -> Void
    private let openDebug: () -> Void
    private let refreshSpaces: () -> Void
    private let resetMenuBarItem: () -> Void

    init(
        store: SpaceStore,
        detector: SpaceDetector,
        openEditor: @escaping () -> Void,
        openOverview: @escaping () -> Void,
        showLabelOverlay: @escaping () -> Void,
        toggleLabelOverlay: @escaping () -> Void,
        openPreferences: @escaping () -> Void,
        openDebug: @escaping () -> Void,
        refreshSpaces: @escaping () -> Void,
        resetMenuBarItem: @escaping () -> Void
    ) {
        self.store = store
        self.detector = detector
        self.openEditor = openEditor
        self.openOverview = openOverview
        self.showLabelOverlay = showLabelOverlay
        self.toggleLabelOverlay = toggleLabelOverlay
        self.openPreferences = openPreferences
        self.openDebug = openDebug
        self.refreshSpaces = refreshSpaces
        self.resetMenuBarItem = resetMenuBarItem
        super.init()
        statusItem.autosaveName = MenuBarStatusItemDefaults.autosaveName
        statusItem.behavior = [.removalAllowed]
    }

    static func resetPersistedSystemPlacement() {
        for autosaveName in MenuBarStatusItemDefaults.knownAutosaveNames {
            UserDefaults.standard.removeObject(forKey: MenuBarStatusItemDefaults.key("Preferred Position", autosaveName: autosaveName))
            UserDefaults.standard.removeObject(forKey: MenuBarStatusItemDefaults.key("Visible", autosaveName: autosaveName))
        }
    }

    func start() {
        rebuildMenu(menu)
        configureStatusItemButton()
        refresh()
    }

    func refresh() {
        // The detector continues polling while a menu is tracking. Replacing its items or
        // moving the status button at that point can cancel the user's selection.
        guard !isMenuTracking else { return }
        let active = activeStatusForMainDisplay()
        lastMenuItemTitles = MenuBarStatusContent.menuItemTitles(for: active.space)
        guard let button = statusItem.button else {
            Self.currentStatusSnapshot = statusSnapshot(for: active)
            return
        }

        let title = MenuBarStatusContent.attributedStatusTitle(for: active.space, settings: store.config.settings)
        statusItem.isVisible = store.config.settings.menuBarLabelPosition != .hidden
        button.image = nil
        button.attributedTitle = title
        button.toolTip = "SpacesUltimate: \(active.desktopLabel) - \(active.displayName). Right-click for Desktop Notes. (\(active.resolution.source))"
        button.setAccessibilityTitle("SpacesUltimate \(active.desktopLabel): \(active.displayName)")
        statusItem.length = statusItemLength(for: title)
        rebuildMenu(menu)
        Self.currentStatusSnapshot = statusSnapshot(for: active)
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func isSettingsMenuInteraction(at point: NSPoint, mouseButton: Int) -> Bool {
        if isMenuTracking { return true }
        // Right-click and Control-click still use the existing notes toggle/dismissal path.
        guard mouseButton == 0, !NSEvent.modifierFlags.contains(.control),
              statusItem.isVisible, let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        switch MenuBarClickIntent.resolve(
            eventType: event?.type,
            modifierFlags: event?.modifierFlags ?? []
        ) {
        case .toggleNotesOverlay:
            toggleLabelOverlay()
        case .showMenu:
            refresh()
            isMenuTracking = true
            defer {
                isMenuTracking = false
                refresh()
            }
            sender.highlight(true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
            sender.highlight(false)
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let active = activeStatusForStatusItemScreen()
        menu.addItem(item(MenuBarStatusContent.currentDesktopMenuTitle(for: active.space), #selector(openPreferencesAction)))
        menu.addItem(.separator())
        menu.addItem(item("SpacesUltimate Settings...", #selector(openPreferencesAction)))
        menu.addItem(item("Open Space Editor", #selector(openEditorAction)))
        menu.addItem(item("Open Overview", #selector(openOverviewAction)))
        menu.addItem(item("Show Desktop Notes Overlay", #selector(showLabelOverlayAction)))
        menu.addItem(displayModeMenuItem())
        menu.addItem(item("Debug Panel", #selector(openDebugAction)))
        menu.addItem(item("Refresh Spaces", #selector(refreshAction)))
        menu.addItem(item("Reset Menu Bar Item", #selector(resetMenuBarItemAction)))
        menu.addItem(.separator())
        menu.addItem(item("Quit SpacesUltimate", #selector(quitAction)))
        lastMenuItemTitles = menu.items.compactMap { item in
            item.isSeparatorItem ? nil : item.title
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func displayModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Status Item Display", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(displayModeItem("Compact Badge", mode: .compact, action: #selector(setCompactDisplayModeAction)))
        submenu.addItem(displayModeItem("Badge + Desktop Name", mode: .numberAndName, action: #selector(setNumberAndNameDisplayModeAction)))
        submenu.addItem(displayModeItem("Desktop Name", mode: .name, action: #selector(setNameDisplayModeAction)))
        submenu.addItem(displayModeItem("Icon + Desktop Name", mode: .iconAndName, action: #selector(setIconAndNameDisplayModeAction)))
        item.submenu = submenu
        return item
    }

    private func displayModeItem(_ title: String, mode: MenuBarDisplayMode, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = store.config.settings.menuBarDisplayMode == mode ? .on : .off
        return item
    }

    private func statusSnapshot(for active: MenuBarActiveStatus) -> MenuBarStatusSnapshot {
        let button = statusItem.button
        let window = button?.window
        let buttonFrameInScreen = button.flatMap { button in
            window.map { window in
                window.convertToScreen(button.convert(button.bounds, to: nil))
            }
        }
        return MenuBarStatusSnapshot(
            autosaveName: MenuBarStatusItemDefaults.autosaveName,
            isVisible: statusItem.isVisible,
            title: button?.attributedTitle.string ?? button?.title ?? "",
            badgeText: MenuBarStatusContent.badgeText(for: active.space),
            toolTip: button?.toolTip,
            menuItemTitles: lastMenuItemTitles,
            screenCount: NSScreen.screens.count,
            activeScreenName: active.screen?.localizedName,
            activeDesktopLabel: active.desktopLabel,
            activeDisplayName: active.displayName,
            statusItemLength: statusItem.length,
            isButtonHidden: button?.isHidden ?? true,
            buttonAlphaValue: button?.alphaValue ?? 0,
            buttonFrameInScreen: buttonFrameInScreen,
            buttonWindowFrame: window?.frame,
            buttonWindowIsVisible: window?.isVisible ?? false,
            buttonWindowNumber: window?.windowNumber ?? 0,
            buttonWindowLevel: window?.level.rawValue ?? 0,
            buttonWindowScreenName: window?.screen?.localizedName,
            buttonWindowOcclusionVisible: window?.occlusionState.contains(.visible) ?? false,
            buttonWindowClassName: window.map { String(describing: type(of: $0)) },
            buttonSuperviewClassName: button?.superview.map { String(describing: type(of: $0)) },
            resolutionSource: active.resolution.source,
            resolutionConfidence: active.resolution.confidence
        )
    }

    private func activeStatusForStatusItemScreen() -> MenuBarActiveStatus {
        let displayStatus = detector.mainDisplayStatus()
        let screen = displayStatus.screen
        let resolution = displayStatus.resolution
        let space = resolution.resolvedOrderIndex.map { store.space(orderIndex: $0) }
            ?? store.space(orderIndex: store.config.lastKnownActiveOrderIndex)
        return MenuBarActiveStatus(screen: screen, resolution: resolution, space: space)
    }

    private func activeStatusForMainDisplay() -> MenuBarActiveStatus {
        let displayStatus = detector.mainDisplayStatus()
        let space = displayStatus.resolution.resolvedOrderIndex.map { store.space(orderIndex: $0) }
            ?? store.space(orderIndex: store.config.lastKnownActiveOrderIndex)
        return MenuBarActiveStatus(screen: displayStatus.screen, resolution: displayStatus.resolution, space: space)
    }

    private func statusItemLength(for title: NSAttributedString) -> CGFloat {
        max(28, ceil(title.size().width) + 14)
    }

    @objc private func openEditorAction() { openEditor() }
    @objc private func openOverviewAction() { openOverview() }
    @objc private func showLabelOverlayAction() { showLabelOverlay() }
    @objc private func openPreferencesAction() { openPreferences() }
    @objc private func openDebugAction() { openDebug() }
    @objc private func refreshAction() { refreshSpaces() }
    @objc private func resetMenuBarItemAction() { resetMenuBarItem() }
    @objc private func setCompactDisplayModeAction() { setDisplayMode(.compact) }
    @objc private func setNameDisplayModeAction() { setDisplayMode(.name) }
    @objc private func setNumberAndNameDisplayModeAction() { setDisplayMode(.numberAndName) }
    @objc private func setIconAndNameDisplayModeAction() { setDisplayMode(.iconAndName) }
    @objc private func quitAction() { NSApp.terminate(nil) }

    private func setDisplayMode(_ mode: MenuBarDisplayMode) {
        var settings = store.config.settings
        settings.menuBarDisplayMode = mode
        if settings.menuBarLabelPosition == .hidden {
            settings.menuBarLabelPosition = .rightOfCenter
        }
        store.updateSettings(settings)
        refresh()
    }
}

enum MenuBarClickIntent: Equatable {
    case showMenu
    case toggleNotesOverlay

    static func resolve(
        eventType: NSEvent.EventType?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> MenuBarClickIntent {
        if eventType == .rightMouseDown || eventType == .rightMouseUp {
            return .toggleNotesOverlay
        }
        if eventType == .leftMouseDown || eventType == .leftMouseUp, modifierFlags.contains(.control) {
            return .toggleNotesOverlay
        }
        return .showMenu
    }
}

enum MenuBarStatusItemDefaults {
    static let autosaveName = "SpacesUltimateStatusItem"
    static let knownAutosaveNames = [
        autosaveName,
        "SpacesUltimateStatusItem2",
        "SpacesUltimateMenuBarItem"
    ]

    static func key(_ key: String, autosaveName: String) -> String {
        "NSStatusItem \(key) \(autosaveName)"
    }
}

enum MenuBarStatusContent {
    static func currentDesktopMenuTitle(for space: SpaceMetadata?) -> String {
        guard let space else { return "Desktop Unknown" }
        let prefix = space.icon.isEmpty ? "" : "\(space.icon) "
        return "\(prefix)\(space.desktopLabel): \(space.displayName)"
    }

    static func menuItemTitles(for space: SpaceMetadata?) -> [String] {
        var titles = [
            currentDesktopMenuTitle(for: space),
            "SpacesUltimate Settings...",
            "Open Space Editor",
            "Open Overview",
            "Show Desktop Notes Overlay",
            "Status Item Display",
            "Debug Panel",
            "Refresh Spaces",
            "Reset Menu Bar Item",
        ]
        titles.append("Quit SpacesUltimate")
        return titles
    }

    static func badgeText(for space: SpaceMetadata?) -> String {
        guard let space else { return "?" }
        return "D\(space.orderIndex)"
    }

    static func badgeSize(for space: SpaceMetadata?) -> NSSize {
        let textWidth = ceil((badgeText(for: space) as NSString).size(withAttributes: badgeTextAttributes()).width)
        return NSSize(width: max(24, textWidth + 10), height: 18)
    }

    static func statusLabel(for space: SpaceMetadata?, settings: AppSettings) -> String {
        let title = statusTitle(for: space, settings: settings)
        let badge = badgeText(for: space)
        return title.isEmpty ? badge : "\(badge) \(title)"
    }

    static func visibleStatusTitle(for space: SpaceMetadata?, settings: AppSettings) -> String {
        let badge = badgeText(for: space)
        let title = statusTitle(for: space, settings: settings)
        return title.isEmpty ? "Spaces \(badge)" : "Spaces \(badge) \(title)"
    }

    static func statusIcon() -> NSImage {
        if let image = NSImage(contentsOfFile: Bundle.main.path(forResource: "SpacesUltimate", ofType: "icns") ?? "") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }
        if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "SpacesUltimate") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 14, height: 14), xRadius: 4, yRadius: 4).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func attributedStatusTitle(for space: SpaceMetadata?, settings: AppSettings) -> NSAttributedString {
        let badge = " \(badgeText(for: space)) "
        let text = statusTitle(for: space, settings: settings)
        let fullTitle = text.isEmpty ? badge : "\(badge) \(text)"
        let color = space.map { NSColor(hex: $0.colorHex) } ?? NSColor.systemBlue
        let title = NSMutableAttributedString(
            string: fullTitle,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            ]
        )
        title.addAttributes(
            [
                .foregroundColor: NSColor.white,
                .backgroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
            ],
            range: NSRange(location: 0, length: badge.count)
        )
        return title
    }

    static func statusTitle(for space: SpaceMetadata?, settings: AppSettings) -> String {
        guard settings.menuBarLabelPosition != .hidden else {
            return ""
        }
        guard let space else {
            return settings.menuBarDisplayMode == .compact ? "" : "Unknown"
        }

        switch settings.menuBarDisplayMode {
        case .name:
            return space.displayName
        case .numberAndName:
            return space.displayName
        case .iconAndName:
            return space.icon.isEmpty ? space.displayName : "\(space.icon) \(space.displayName)"
        case .compact:
            return ""
        }
    }

    static func badgeImage(for space: SpaceMetadata?) -> NSImage {
        let size = badgeSize(for: space)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        (space.map { NSColor(hex: $0.colorHex) } ?? NSColor.systemGray).setFill()
        path.fill()

        let text = badgeText(for: space) as NSString
        let attributes = badgeTextAttributes()
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: floor((size.width - textSize.width) / 2),
                y: floor((size.height - textSize.height) / 2)
            ),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func badgeTextAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        ]
    }
}
