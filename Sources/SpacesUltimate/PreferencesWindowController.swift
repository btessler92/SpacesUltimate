import AppKit

enum PreferencesCategory: Int, CaseIterable {
    case notes, overview, menuBar, startup, screenshots, permissions, advanced, defaults

    var title: String {
        switch self {
        case .notes: "Desktop Notes"
        case .overview: "HUD & Overview"
        case .menuBar: "Menu Bar"
        case .startup: "Startup"
        case .screenshots: "Screenshots"
        case .permissions: "Permissions"
        case .advanced: "Advanced"
        case .defaults: "Defaults & Reset"
        }
    }

    var summary: String {
        switch self {
        case .notes: "Adjust the notes overlay that appears with Mission Control."
        case .overview: "Choose how to see the current Desktop and open the overview."
        case .menuBar: "Choose what SpacesUltimate displays in the menu bar."
        case .startup: "Choose what opens automatically."
        case .screenshots: "Choose where diagnostic screenshots are saved."
        case .permissions: "Manage the access needed for Desktop switching and screenshots."
        case .advanced: "Connect local tools and automations to SpacesUltimate."
        case .defaults: "Save your preferred setup or restore default values."
        }
    }

    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .overview: "rectangle.on.rectangle"
        case .menuBar: "menubar.rectangle"
        case .startup: "power"
        case .screenshots: "photo"
        case .permissions: "lock.shield"
        case .advanced: "slider.horizontal.3"
        case .defaults: "arrow.counterclockwise"
        }
    }
}

private enum HUDSlider: Int, CaseIterable {
    case fadeIn, hold, fadeOut, size, background

    var title: String {
        switch self {
        case .fadeIn: "Fade in"
        case .hold: "Fully visible"
        case .fadeOut: "Fade out"
        case .size: "Size"
        case .background: "Opacity"
        }
    }

    var keyPath: WritableKeyPath<AppSettings, Double> {
        switch self {
        case .fadeIn: \.hudFadeInSeconds
        case .hold: \.hudHoldSeconds
        case .fadeOut: \.hudDurationSeconds
        case .size: \.hudScale
        case .background: \.hudBackgroundOpacity
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .fadeIn: 0...3
        case .hold: 0...10
        case .fadeOut: 0.2...10
        case .size: 0.7...1.5
        case .background: 0.15...1
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .size, .background: String(format: "%.0f%%", value * 100)
        default: String(format: "%.1f s", value)
        }
    }
}

final class PreferencesWindowController: NSWindowController {
    private let store: SpaceStore
    private let scanner: WindowScanner
    private let screenshotService: ScreenshotService
    private let loginItemController: LoginItemController
    private let previewHUD: (AppSettings) -> Void
    private let categoryScroll = NSScrollView()
    private let categoryDocument = PreferencesDocumentView()
    private var categoryPages: [PreferencesCategory: NSStackView] = [:]
    private var categoryButtons: [PreferencesCategory: NSButton] = [:]
    private var pageConstraints: [NSLayoutConstraint] = []
    private(set) var selectedCategory = PreferencesCategory.notes
    private let defaultsStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let saveDefaultButton = NSButton(title: "Save Current as Default", target: nil, action: nil)
    private let restoreDefaultButton = NSButton(title: "Restore Default", target: nil, action: nil)
    private let factoryResetButton = NSButton(title: "Factory Reset", target: nil, action: nil)
    private let showDefaultValuesButton = NSButton(checkboxWithTitle: "Show default values", target: nil, action: nil)
    private let defaultsTableContainer = NSStackView()
    private var displayedDefaultValues: [String] = []
    private let hudEnabled = NSButton(checkboxWithTitle: "Show a label when the active Desktop changes", target: nil, action: nil)
    private let apiEnabled = NSButton(checkboxWithTitle: "Enable localhost control API", target: nil, action: nil)
    private let hotkeyEnabled = NSButton(checkboxWithTitle: "Enable the overview keyboard shortcut", target: nil, action: nil)
    private let notesOverlayHotkeyEnabled = NSButton(checkboxWithTitle: "Enable the notes overlay keyboard shortcut", target: nil, action: nil)
    private let autoLaunchApps = NSButton(checkboxWithTitle: "Auto-launch assigned apps when a Space becomes active", target: nil, action: nil)
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch SpacesUltimate at login", target: nil, action: nil)
    private var hudSliders: [HUDSlider: NSSlider] = [:]
    private var hudValueLabels: [HUDSlider: NSTextField] = [:]
    private var hudResetButtons: [HUDSlider: NSButton] = [:]
    private let hudPositionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hudShowsDesktopNumber = NSButton(checkboxWithTitle: "Show Desktop number", target: nil, action: nil)
    private let notesOverlayOpacitySlider = NSSlider(value: AppSettings.defaults.notesOverlayItemOpacity, minValue: 0.12, maxValue: 0.90, target: nil, action: nil)
    private let notesOverlayOpacityLabel = NSTextField(labelWithString: "")
    private let resetNotesOverlayOpacityButton = NSButton(title: "Default", target: nil, action: nil)
    private let notesOverlayBackgroundOpacitySlider = NSSlider(value: AppSettings.defaults.notesOverlayBackgroundOpacity, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let notesOverlayBackgroundOpacityLabel = NSTextField(labelWithString: "")
    private let resetNotesOverlayBackgroundOpacityButton = NSButton(title: "Default", target: nil, action: nil)
    private let notesOverlayHeightSlider = NSSlider(
        value: AppSettings.defaults.notesOverlayHeightPixels,
        minValue: AppSettings.minimumNotesOverlayHeightPixels,
        maxValue: AppSettings.maximumNotesOverlayHeightPixels,
        target: nil,
        action: nil
    )
    private let notesOverlayHeightLabel = NSTextField(labelWithString: "")
    private let resetNotesOverlayHeightButton = NSButton(title: "Default", target: nil, action: nil)
    private let hotkeyShortcutLabel = NSTextField(labelWithString: "Shortcut:")
    private let hotkeyShortcutField = NSTextField(string: AppSettings.defaults.globalHotkeyShortcut)
    private let notesOverlayHotkeyShortcutLabel = NSTextField(labelWithString: "Shortcut:")
    private let notesOverlayHotkeyShortcutField = NSTextField(string: AppSettings.defaults.notesOverlayHotkeyShortcut)
    private let menuBarModeLabel = NSTextField(labelWithString: "Show:")
    private let menuBarModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuBarLabelPositionLabel = NSTextField(labelWithString: "Visibility:")
    private let menuBarLabelPositionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let screenshotDirectoryLabel = NSTextField(labelWithString: "")
    private let chooseScreenshotDirectoryButton = NSButton(title: "Choose Screenshot Directory", target: nil, action: nil)
    private let resetScreenshotDirectoryButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private let screenCaptureLabel = NSTextField(labelWithString: "")
    private let permissionTargetLabel = NSTextField(labelWithString: "")
    private let loginItemLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "Request Accessibility Permission", target: nil, action: nil)
    private let screenCaptureButton = NSButton(title: "Request Screen Recording Permission", target: nil, action: nil)

    init(store: SpaceStore, scanner: WindowScanner, screenshotService: ScreenshotService,
         loginItemController: LoginItemController, previewHUD: @escaping (AppSettings) -> Void = { _ in }) {
        self.store = store
        self.scanner = scanner
        self.screenshotService = screenshotService
        self.loginItemController = loginItemController
        self.previewHUD = previewHUD
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 690),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpacesUltimate Preferences"
        window.contentMinSize = NSSize(width: 860, height: 650)
        window.center()
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        // Reopening Settings must not restore a hotkey field's previous editing focus.
        window?.makeFirstResponder(window?.initialFirstResponder)
    }

    func reloadIfVisible() {
        guard window?.isVisible == true else { return }
        reload()
    }

    func ownsInteraction(in eventWindow: NSWindow?, at screenPoint: NSPoint) -> Bool {
        guard let window, window.isVisible, !window.isMiniaturized else { return false }
        // During Mission Control, Dock can consume the click before AppKit supplies a window.
        if eventWindow == nil, NSApp.isActive, window.isKeyWindow || window.attachedSheet?.isKeyWindow == true {
            return window.frame.contains(screenPoint) || window.attachedSheet?.frame.contains(screenPoint) == true
        }
        var candidate = eventWindow
        while let current = candidate {
            if current === window { return true }
            candidate = current.sheetParent ?? current.parent
        }
        return false
    }

    func reload() {
        let settings = store.config.settings
        let defaults = store.preferenceDefaults.settings
        reloadDefaultsSummary()
        hudEnabled.state = settings.hudEnabled ? .on : .off
        apiEnabled.state = settings.apiEnabled ? .on : .off
        hotkeyEnabled.state = settings.globalHotkeyEnabled ? .on : .off
        notesOverlayHotkeyEnabled.state = settings.notesOverlayHotkeyEnabled ? .on : .off
        autoLaunchApps.state = settings.autoLaunchAssignedApps ? .on : .off
        launchAtLogin.state = loginItemController.isEnabled ? .on : .off
        for kind in HUDSlider.allCases {
            hudSliders[kind]?.doubleValue = settings[keyPath: kind.keyPath]
            hudValueLabels[kind]?.stringValue = kind.formatted(settings[keyPath: kind.keyPath])
            let defaultValue = "Default: \(kind.formatted(defaults[keyPath: kind.keyPath]))"
            hudValueLabels[kind]?.toolTip = defaultValue
            hudResetButtons[kind]?.toolTip = defaultValue
        }
        hudPositionPopup.selectItem(withTitle: settings.hudPosition.label)
        hudShowsDesktopNumber.state = settings.hudShowsDesktopNumber ? .on : .off
        notesOverlayOpacitySlider.doubleValue = settings.notesOverlayItemOpacity
        notesOverlayOpacityLabel.stringValue = String(format: "Notes card opacity: %.0f%% (default: %.0f%%)", settings.notesOverlayItemOpacity * 100, defaults.notesOverlayItemOpacity * 100)
        notesOverlayBackgroundOpacitySlider.doubleValue = settings.notesOverlayBackgroundOpacity
        notesOverlayBackgroundOpacityLabel.stringValue = String(format: "Notes background opacity: %.0f%% (default: %.0f%%)", settings.notesOverlayBackgroundOpacity * 100, defaults.notesOverlayBackgroundOpacity * 100)
        notesOverlayHeightSlider.doubleValue = settings.notesOverlayHeightPixels
        notesOverlayHeightLabel.stringValue = String(format: "Row height: %.0f px (default: %.0f px)", settings.notesOverlayHeightPixels, defaults.notesOverlayHeightPixels)
        hotkeyShortcutField.stringValue = settings.globalHotkeyShortcut
        notesOverlayHotkeyShortcutField.stringValue = settings.notesOverlayHotkeyShortcut
        selectMenuBarMode(settings.menuBarDisplayMode)
        selectMenuBarLabelPosition(settings.menuBarLabelPosition)
        let screenshotDirectory = screenshotService.screenshotsDirectory.path
        screenshotDirectoryLabel.stringValue = "Screenshots: \(screenshotDirectory)"
        resetScreenshotDirectoryButton.isEnabled = !settings.screenshotDirectoryPath.isEmpty
        permissionLabel.stringValue = scanner.isAccessibilityTrusted
            ? "Accessibility: granted"
            : "Accessibility: not granted. Global hotkey and richer scanning may be limited."
        screenCaptureLabel.stringValue = screenshotService.isScreenCaptureTrusted
            ? "Screen Recording: granted"
            : "Screen Recording: not granted. Screenshot diagnostics are disabled until granted."
        permissionTargetLabel.stringValue = "Permission target: \(AppIdentity.permissionTargetSummary)"
        let loginState = loginItemController.state
        loginItemLabel.stringValue = "Launch at login: \(loginState.status). \(loginState.recoverySuggestion)"
        accessibilityButton.isEnabled = !scanner.isAccessibilityTrusted
        screenCaptureButton.isEnabled = !screenshotService.isScreenCaptureTrusted
        accessibilityButton.title = scanner.isAccessibilityTrusted ? "Accessibility Granted" : "Request Accessibility Permission"
        screenCaptureButton.title = screenshotService.isScreenCaptureTrusted ? "Screen Recording Granted" : "Request Screen Recording Permission"
    }

    private func build() {
        guard let contentView = window?.contentView else { return }

        let sidebar = NSVisualEffectView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        let navigation = NSStackView()
        navigation.translatesAutoresizingMaskIntoConstraints = false
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 6
        let sidebarTitle = NSTextField(labelWithString: "Preferences")
        sidebarTitle.font = .boldSystemFont(ofSize: 13)
        sidebarTitle.textColor = .secondaryLabelColor
        navigation.addArrangedSubview(sidebarTitle)
        navigation.setCustomSpacing(16, after: sidebarTitle)
        for category in PreferencesCategory.allCases {
            let button = NSButton(title: category.title, target: self, action: #selector(categoryClicked(_:)))
            button.tag = category.rawValue
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .recessed
            button.alignment = .left
            button.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.widthAnchor.constraint(equalToConstant: 160).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            navigation.addArrangedSubview(button)
            categoryButtons[category] = button
            categoryPages[category] = makePage(category)
        }
        sidebar.addSubview(navigation)
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        categoryScroll.translatesAutoresizingMaskIntoConstraints = false
        categoryScroll.hasVerticalScroller = true
        categoryScroll.drawsBackground = false
        categoryDocument.translatesAutoresizingMaskIntoConstraints = false
        categoryScroll.documentView = categoryDocument
        // Keep a neutral focus target when opening Preferences or changing categories.
        window?.initialFirstResponder = categoryDocument
        contentView.addSubview(sidebar)
        contentView.addSubview(divider)
        contentView.addSubview(categoryScroll)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 184),
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24),
            navigation.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor, constant: -24),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: contentView.topAnchor),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            categoryScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            categoryScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            categoryScroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            categoryScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            categoryDocument.widthAnchor.constraint(equalTo: categoryScroll.contentView.widthAnchor)
        ])

        [hudEnabled, hudShowsDesktopNumber, apiEnabled, hotkeyEnabled, notesOverlayHotkeyEnabled, autoLaunchApps].forEach {
            $0.target = self
            $0.action = #selector(settingChanged)
        }
        launchAtLogin.target = self
        launchAtLogin.action = #selector(launchAtLoginChanged)
        [hotkeyShortcutField, notesOverlayHotkeyShortcutField].forEach {
            $0.target = self
            $0.action = #selector(settingChanged)
            $0.widthAnchor.constraint(equalToConstant: 210).isActive = true
        }
        hotkeyShortcutField.setAccessibilityLabel("Overview keyboard shortcut")
        notesOverlayHotkeyShortcutField.setAccessibilityLabel("Notes overlay keyboard shortcut")

        let notes = categoryPages[.notes]!
        addSubheading("Appearance", to: notes)
        configureSlider(notesOverlayOpacitySlider, label: notesOverlayOpacityLabel,
                        reset: resetNotesOverlayOpacityButton, action: #selector(resetNotesOverlayOpacity), in: notes)
        notesOverlayOpacitySlider.isContinuous = true
        notesOverlayOpacitySlider.setAccessibilityLabel("Notes card opacity")
        configureSlider(notesOverlayBackgroundOpacitySlider, label: notesOverlayBackgroundOpacityLabel,
                        reset: resetNotesOverlayBackgroundOpacityButton, action: #selector(resetNotesOverlayBackgroundOpacity), in: notes)
        notesOverlayBackgroundOpacitySlider.isContinuous = true
        notesOverlayBackgroundOpacitySlider.setAccessibilityLabel("Notes background opacity")
        configureSlider(notesOverlayHeightSlider, label: notesOverlayHeightLabel,
                        reset: resetNotesOverlayHeightButton, action: #selector(resetNotesOverlayHeight), in: notes)
        addExplanation("Crowded displays use two compact rows, with small Go buttons inside the cards to save height.", to: notes)
        addSubheading("Keyboard shortcut", to: notes)
        notes.addArrangedSubview(notesOverlayHotkeyEnabled)
        notes.addArrangedSubview(row([notesOverlayHotkeyShortcutLabel, notesOverlayHotkeyShortcutField]))
        addExplanation("Notes also open automatically with Mission Control.", to: notes)

        let overview = categoryPages[.overview]!
        addSubheading("Desktop change notification", to: overview)
        addExplanation("The HUD is a brief label showing which Desktop you switched to.", to: overview)
        overview.addArrangedSubview(hudEnabled)
        let testHUD = NSButton(title: "Test HUD for Current Desktop", target: self, action: #selector(testHUDClicked))
        testHUD.bezelStyle = .rounded
        overview.addArrangedSubview(testHUD)
        addExplanation("Preview your current Desktop, even when automatic notifications are off.", to: overview)
        addSubheading("Timing", to: overview)
        for kind in [HUDSlider.fadeIn, .hold, .fadeOut] { addHUDSlider(kind, to: overview) }
        addExplanation("Fade in, stay fully visible, then fade out. Increase Fade out for a slower disappearance.", to: overview)
        addSubheading("Appearance", to: overview)
        for kind in [HUDSlider.size, .background] { addHUDSlider(kind, to: overview) }
        for position in HUDPosition.allCases {
            hudPositionPopup.addItem(withTitle: position.label)
            hudPositionPopup.lastItem?.representedObject = position.rawValue
        }
        hudPositionPopup.target = self
        hudPositionPopup.action = #selector(settingChanged)
        hudPositionPopup.setAccessibilityLabel("HUD position")
        overview.addArrangedSubview(row([NSTextField(labelWithString: "Position:"), hudPositionPopup, hudShowsDesktopNumber]))
        addSubheading("Overview", to: overview)
        overview.addArrangedSubview(hotkeyEnabled)
        overview.addArrangedSubview(row([hotkeyShortcutLabel, hotkeyShortcutField]))

        let menuBar = categoryPages[.menuBar]!
        for mode in MenuBarDisplayMode.allCases {
            menuBarModePopup.addItem(withTitle: mode.label)
            menuBarModePopup.lastItem?.representedObject = mode.rawValue
        }
        menuBarModePopup.target = self
        menuBarModePopup.action = #selector(settingChanged)
        menuBar.addArrangedSubview(row([menuBarModeLabel, menuBarModePopup]))
        menuBarLabelPositionPopup.addItem(withTitle: "Shown")
        menuBarLabelPositionPopup.lastItem?.representedObject = MenuBarLabelPosition.rightOfCenter.rawValue
        menuBarLabelPositionPopup.addItem(withTitle: "Hidden")
        menuBarLabelPositionPopup.lastItem?.representedObject = MenuBarLabelPosition.hidden.rawValue
        menuBarLabelPositionPopup.target = self
        menuBarLabelPositionPopup.action = #selector(settingChanged)
        menuBar.addArrangedSubview(row([menuBarLabelPositionLabel, menuBarLabelPositionPopup]))

        let startup = categoryPages[.startup]!
        addSubheading("When you sign in", to: startup)
        startup.addArrangedSubview(launchAtLogin)
        configureWrappingLabel(loginItemLabel, in: startup)
        addSubheading("When you switch Desktops", to: startup)
        startup.addArrangedSubview(autoLaunchApps)
        addExplanation("Uses the apps assigned to each Desktop in the Space Editor.", to: startup)

        let screenshots = categoryPages[.screenshots]!
        addSubheading("Save location", to: screenshots)
        configureWrappingLabel(screenshotDirectoryLabel, in: screenshots)
        chooseScreenshotDirectoryButton.target = self
        chooseScreenshotDirectoryButton.action = #selector(chooseScreenshotDirectory)
        chooseScreenshotDirectoryButton.bezelStyle = .rounded
        resetScreenshotDirectoryButton.target = self
        resetScreenshotDirectoryButton.action = #selector(resetScreenshotDirectory)
        resetScreenshotDirectoryButton.bezelStyle = .rounded
        screenshots.addArrangedSubview(row([chooseScreenshotDirectoryButton, resetScreenshotDirectoryButton]))
        addExplanation("Screen Recording access can be managed in Permissions.", to: screenshots)

        let permissions = categoryPages[.permissions]!
        addSubheading("Accessibility", to: permissions)
        configureWrappingLabel(permissionLabel, in: permissions)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibility)
        accessibilityButton.bezelStyle = .rounded
        permissions.addArrangedSubview(accessibilityButton)
        addSubheading("Screen Recording", to: permissions)
        configureWrappingLabel(screenCaptureLabel, in: permissions)
        screenCaptureButton.target = self
        screenCaptureButton.action = #selector(requestScreenCapture)
        screenCaptureButton.bezelStyle = .rounded
        permissions.addArrangedSubview(screenCaptureButton)
        addSubheading("App receiving access", to: permissions)
        configureWrappingLabel(permissionTargetLabel, in: permissions)

        let advanced = categoryPages[.advanced]!
        addSubheading("Local control API", to: advanced)
        advanced.addArrangedSubview(apiEnabled)
        addExplanation("Allows tools on this Mac to read and change SpacesUltimate settings.", to: advanced)
        buildDefaultsControls(in: categoryPages[.defaults]!)
        selectCategory(.notes)
    }

    private func makePage(_ category: PreferencesCategory) -> NSStackView {
        let page = NSStackView()
        page.translatesAutoresizingMaskIntoConstraints = false
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 12
        page.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let heading = NSTextField(labelWithString: category.title)
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        page.addArrangedSubview(heading)
        addExplanation(category.summary, to: page)
        return page
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func addSubheading(_ title: String, to page: NSStackView) {
        if let previous = page.arrangedSubviews.last { page.setCustomSpacing(24, after: previous) }
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        page.addArrangedSubview(heading)
    }

    private func configureWrappingLabel(_ label: NSTextField, in page: NSStackView) {
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.cell?.usesSingleLineMode = false
        label.cell?.wraps = true
        label.preferredMaxLayoutWidth = 620
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        page.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -48).isActive = true
    }

    private func addExplanation(_ text: String, to page: NSStackView) {
        configureWrappingLabel(NSTextField(wrappingLabelWithString: text), in: page)
    }

    private func configureSlider(_ slider: NSSlider, label: NSTextField,
                                 reset: NSButton? = nil, action: Selector? = nil, in page: NSStackView) {
        slider.target = self
        slider.action = #selector(settingChanged)
        slider.widthAnchor.constraint(equalToConstant: 290).isActive = true
        page.addArrangedSubview(label)
        page.setCustomSpacing(6, after: label)
        if let reset {
            reset.target = self
            reset.action = action
            reset.bezelStyle = .rounded
            reset.controlSize = .small
            page.addArrangedSubview(row([slider, reset]))
        } else {
            page.addArrangedSubview(slider)
        }
    }

    private func addHUDSlider(_ kind: HUDSlider, to page: NSStackView) {
        let label = NSTextField(labelWithString: kind.title)
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let slider = NSSlider(value: AppSettings.defaults[keyPath: kind.keyPath],
            minValue: kind.range.lowerBound, maxValue: kind.range.upperBound,
            target: self, action: #selector(settingChanged))
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        slider.setAccessibilityLabel("HUD \(kind.title.lowercased())")
        if kind == .background {
            slider.setAccessibilityLabel("HUD background opacity")
            slider.toolTip = "Changes the background opacity while keeping text fully visible."
        }
        let value = NSTextField(labelWithString: "")
        value.widthAnchor.constraint(equalToConstant: 64).isActive = true
        value.alignment = .right
        let reset = NSButton(title: "Default", target: self, action: #selector(resetHUDSlider(_:)))
        reset.tag = kind.rawValue
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        hudSliders[kind] = slider
        hudValueLabels[kind] = value
        hudResetButtons[kind] = reset
        page.addArrangedSubview(row([label, slider, value, reset]))
    }

    @objc private func resetHUDSlider(_ sender: NSButton) {
        guard let kind = HUDSlider(rawValue: sender.tag) else { return }
        hudSliders[kind]?.doubleValue = store.preferenceDefaults.settings[keyPath: kind.keyPath]
        settingChanged()
    }

    @objc private func testHUDClicked() {
        settingChanged()
        previewHUD(store.config.settings)
    }

    @objc private func categoryClicked(_ sender: NSButton) {
        guard let category = PreferencesCategory(rawValue: sender.tag) else { return }
        selectCategory(category)
    }

    func selectCategory(_ category: PreferencesCategory) {
        guard let page = categoryPages[category] else { return }
        window?.makeFirstResponder(categoryDocument)
        NSLayoutConstraint.deactivate(pageConstraints)
        categoryDocument.subviews.forEach { $0.removeFromSuperview() }
        categoryDocument.addSubview(page)
        pageConstraints = [
            page.leadingAnchor.constraint(equalTo: categoryDocument.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: categoryDocument.trailingAnchor),
            page.topAnchor.constraint(equalTo: categoryDocument.topAnchor),
            page.bottomAnchor.constraint(equalTo: categoryDocument.bottomAnchor)
        ]
        NSLayoutConstraint.activate(pageConstraints)
        selectedCategory = category
        for (item, button) in categoryButtons {
            button.state = item == category ? .on : .off
            button.showsBorderOnlyWhileMouseInside = item != category
            button.font = .systemFont(ofSize: 13, weight: item == category ? .semibold : .regular)
            button.contentTintColor = item == category ? .controlAccentColor : .labelColor
        }
        window?.contentView?.layoutSubtreeIfNeeded()
        categoryScroll.contentView.scroll(to: .zero)
        categoryScroll.reflectScrolledClipView(categoryScroll.contentView)
    }

    @objc private func settingChanged() {
        var settings = AppSettings(
            hudEnabled: hudEnabled.state == .on,
            hudDurationSeconds: store.config.settings.hudDurationSeconds,
            apiEnabled: apiEnabled.state == .on,
            globalHotkeyEnabled: hotkeyEnabled.state == .on,
            onboardingCompleted: store.config.settings.onboardingCompleted,
            screenshotDirectoryPath: store.config.settings.screenshotDirectoryPath,
            menuBarDisplayMode: selectedMenuBarMode(),
            menuBarLabelPosition: selectedMenuBarLabelPosition(),
            globalHotkeyShortcut: hotkeyShortcutField.stringValue,
            notesOverlayHotkeyEnabled: notesOverlayHotkeyEnabled.state == .on,
            notesOverlayHotkeyShortcut: notesOverlayHotkeyShortcutField.stringValue,
            notesOverlayItemOpacity: notesOverlayOpacitySlider.doubleValue,
            notesOverlayBackgroundOpacity: notesOverlayBackgroundOpacitySlider.doubleValue,
            notesOverlayHeightPixels: notesOverlayHeightSlider.doubleValue,
            autoLaunchAssignedApps: autoLaunchApps.state == .on
        ).normalized
        for kind in HUDSlider.allCases {
            if let value = hudSliders[kind]?.doubleValue { settings[keyPath: kind.keyPath] = value }
        }
        settings.hudPosition = (hudPositionPopup.selectedItem?.representedObject as? String)
            .flatMap(HUDPosition.init(rawValue:)) ?? .right
        settings.hudShowsDesktopNumber = hudShowsDesktopNumber.state == .on
        settings = settings.normalized
        store.updateSettings(settings)
        reload()
    }

    @objc private func resetNotesOverlayOpacity() {
        notesOverlayOpacitySlider.doubleValue = store.preferenceDefaults.settings.notesOverlayItemOpacity
        settingChanged()
    }

    @objc private func resetNotesOverlayBackgroundOpacity() {
        notesOverlayBackgroundOpacitySlider.doubleValue = store.preferenceDefaults.settings.notesOverlayBackgroundOpacity
        settingChanged()
    }

    @objc private func resetNotesOverlayHeight() {
        notesOverlayHeightSlider.doubleValue = store.preferenceDefaults.settings.notesOverlayHeightPixels
        settingChanged()
    }

    private func buildDefaultsControls(in stack: NSStackView) {
        defaultsStatusLabel.font = .systemFont(ofSize: 12)
        defaultsStatusLabel.preferredMaxLayoutWidth = 600
        defaultsStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(defaultsStatusLabel)
        saveDefaultButton.target = self
        saveDefaultButton.action = #selector(saveCurrentAsDefault)
        saveDefaultButton.toolTip = "Save these preferences and Launch at Login as your new default."
        restoreDefaultButton.target = self
        restoreDefaultButton.action = #selector(restoreDefault)
        restoreDefaultButton.toolTip = "Apply your saved default, or factory settings if you have not saved one."
        factoryResetButton.target = self
        factoryResetButton.action = #selector(factoryReset)
        factoryResetButton.toolTip = "Restore the original preferences and turn Launch at Login off. Your saved default is kept."
        let buttons = NSStackView(views: [saveDefaultButton, restoreDefaultButton, factoryResetButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        [saveDefaultButton, restoreDefaultButton, factoryResetButton].forEach { $0.bezelStyle = .rounded }
        stack.addArrangedSubview(buttons)
        let scope = NSTextField(wrappingLabelWithString: "Factory Reset keeps your saved default. Desktop names, notes and macOS permissions are unchanged.")
        scope.font = .systemFont(ofSize: 11)
        scope.preferredMaxLayoutWidth = 600
        scope.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scope.textColor = .secondaryLabelColor
        stack.addArrangedSubview(scope)
        showDefaultValuesButton.target = self
        showDefaultValuesButton.action = #selector(toggleDefaultValues)
        stack.addArrangedSubview(showDefaultValuesButton)
        defaultsTableContainer.orientation = .vertical
        defaultsTableContainer.alignment = .leading
        defaultsTableContainer.isHidden = true
        stack.addArrangedSubview(defaultsTableContainer)
        NSLayoutConstraint.activate([
            defaultsStatusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            scope.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48)
        ])
    }

    private func reloadDefaultsSummary() {
        let preset = store.preferenceDefaults
        let source: String
        if let saved = store.config.savedPreferenceDefaults {
            let date = saved.savedAt.map { " · saved \(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short))" } ?? ""
            source = "Your saved default\(date)"
        } else {
            source = "Factory settings (no saved default yet)"
        }
        let matches = preset.matches(store.config.settings, launchAtLogin: loginItemController.isEnabled)
        defaultsStatusLabel.stringValue = "Default: \(source).\nCurrent preferences \(matches ? "match" : "differ from") this default."
        restoreDefaultButton.isEnabled = !matches
        factoryResetButton.isEnabled = !PreferenceDefaults.factory.matches(store.config.settings, launchAtLogin: loginItemController.isEnabled)
        let defaults = preset.displayedValues
        let factory = PreferenceDefaults.factory.displayedValues
        let values = defaults.map(\.value) + factory.map(\.value)
        guard values != displayedDefaultValues else { return }
        displayedDefaultValues = values
        for view in defaultsTableContainer.arrangedSubviews {
            defaultsTableContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        var rows = [["Preference", "Default", "Factory"]]
        rows += zip(defaults, factory).map { [$0.name, $0.value, $1.value] }
        let cells: [[NSView]] = rows.enumerated().map { index, row in
            row.map { value in
                let field = NSTextField(labelWithString: value)
                field.font = index == 0 ? .boldSystemFont(ofSize: 11) : .systemFont(ofSize: 11)
                field.lineBreakMode = .byTruncatingMiddle
                field.toolTip = value
                field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                return field
            }
        }
        let grid = NSGridView(views: cells)
        grid.columnSpacing = 12
        grid.rowSpacing = 6
        grid.column(at: 0).width = 170
        grid.column(at: 1).width = 185
        grid.column(at: 2).width = 185
        defaultsTableContainer.addArrangedSubview(grid)
    }

    @objc private func toggleDefaultValues() {
        defaultsTableContainer.isHidden = showDefaultValuesButton.state != .on
    }

    @objc private func saveCurrentAsDefault() {
        // Capture deliberate edits still present in either shortcut field as well.
        settingChanged()
        store.saveCurrentPreferencesAsDefault(launchAtLogin: loginItemController.isEnabled)
        reload()
    }

    @objc private func restoreDefault() {
        applyPreferenceDefaults(store.preferenceDefaults)
    }

    @objc private func factoryReset() {
        applyPreferenceDefaults(.factory)
    }

    private func applyPreferenceDefaults(_ preset: PreferenceDefaults) {
        do {
            if loginItemController.isEnabled != preset.launchAtLogin {
                try loginItemController.setEnabled(preset.launchAtLogin)
            }
            store.restorePreferences(from: preset)
            reload()
            window?.makeFirstResponder(window?.initialFirstResponder)
        } catch {
            AppLog.shared.error("Could not restore preference defaults: \(error.localizedDescription)")
            if let window { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }

    @objc private func requestAccessibility() {
        scanner.requestAccessibilityIfNeeded()
        reload()
    }

    @objc private func requestScreenCapture() {
        _ = screenshotService.requestScreenCaptureIfNeeded()
        reload()
    }

    @objc private func launchAtLoginChanged() {
        do {
            try loginItemController.setEnabled(launchAtLogin.state == .on)
        } catch {
            AppLog.shared.error("Launch at login update failed: \(error.localizedDescription)")
            let alert = NSAlert(error: error)
            if let window {
                alert.beginSheetModal(for: window)
            }
        }
        reload()
    }

    @objc private func chooseScreenshotDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = screenshotService.screenshotsDirectory
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            var settings = self.store.config.settings
            settings.screenshotDirectoryPath = url.path
            self.store.updateSettings(settings)
            self.reload()
        }
    }

    @objc private func resetScreenshotDirectory() {
        var settings = store.config.settings
        settings.screenshotDirectoryPath = ""
        store.updateSettings(settings)
        reload()
    }

    private func selectedMenuBarMode() -> MenuBarDisplayMode {
        guard let rawValue = menuBarModePopup.selectedItem?.representedObject as? String,
              let mode = MenuBarDisplayMode(rawValue: rawValue) else {
            return AppSettings.defaults.menuBarDisplayMode
        }
        return mode
    }

    private func selectMenuBarMode(_ mode: MenuBarDisplayMode) {
        guard let index = menuBarModePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == mode.rawValue }) else {
            return
        }
        menuBarModePopup.selectItem(at: index)
    }

    private func selectedMenuBarLabelPosition() -> MenuBarLabelPosition {
        guard let rawValue = menuBarLabelPositionPopup.selectedItem?.representedObject as? String,
              let position = MenuBarLabelPosition(rawValue: rawValue) else {
            return AppSettings.defaults.menuBarLabelPosition
        }
        return position
    }

    private func selectMenuBarLabelPosition(_ position: MenuBarLabelPosition) {
        let selectedPosition: MenuBarLabelPosition = position == .hidden ? .hidden : .rightOfCenter
        guard let index = menuBarLabelPositionPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selectedPosition.rawValue }) else {
            return
        }
        menuBarLabelPositionPopup.selectItem(at: index)
    }
}

private final class PreferencesDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
