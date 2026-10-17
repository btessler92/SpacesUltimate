import AppKit

final class SpaceEditorWindowController: NSWindowController {
    private let store: SpaceStore
    private let detector: SpaceDetector
    private let scanner: WindowScanner
    private let bridge: NativeBridge
    private let appLaunchService: AppLaunchService
    private let screenshotService: ScreenshotService
    private let previewService: SpacePreviewService
    private let showHUD: (SpaceMetadata) -> Void
    private let showOverview: () -> Void
    private let showLabelOverlay: () -> Void
    private let showPreferences: () -> Void
    private let stack = NSStackView()
    private let scrollDocument = NSView()
    private var preferencesButton: NSButton?

    init(
        store: SpaceStore,
        detector: SpaceDetector,
        scanner: WindowScanner,
        bridge: NativeBridge,
        appLaunchService: AppLaunchService,
        screenshotService: ScreenshotService,
        previewService: SpacePreviewService,
        showHUD: @escaping (SpaceMetadata) -> Void,
        showOverview: @escaping () -> Void,
        showLabelOverlay: @escaping () -> Void,
        showPreferences: @escaping () -> Void
    ) {
        self.store = store
        self.detector = detector
        self.scanner = scanner
        self.bridge = bridge
        self.appLaunchService = appLaunchService
        self.screenshotService = screenshotService
        self.previewService = previewService
        self.showHUD = showHUD
        self.showOverview = showOverview
        self.showLabelOverlay = showLabelOverlay
        self.showPreferences = showPreferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpacesUltimate"
        window.minSize = NSSize(width: 900, height: 520)
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
        fitWindowToVisibleScreen()
        window?.makeKeyAndOrderFront(sender)
    }

    private func build() {
        guard let contentView = window?.contentView else { return }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scrollDocument.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scrollDocument.addSubview(stack)
        scroll.documentView = scrollDocument

        let toolbarScroll = NSScrollView()
        toolbarScroll.translatesAutoresizingMaskIntoConstraints = false
        toolbarScroll.hasHorizontalScroller = true
        toolbarScroll.hasVerticalScroller = false
        toolbarScroll.borderType = .noBorder
        toolbarScroll.drawsBackground = false

        let toolbar = NSStackView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 10, right: 16)
        toolbar.addArrangedSubview(button("Refresh Spaces", #selector(refreshSpaces)))
        toolbar.addArrangedSubview(button("Reset Names", #selector(resetNames)))
        toolbar.addArrangedSubview(button("Backup Config", #selector(backupConfig)))
        toolbar.addArrangedSubview(button("Restore Backup", #selector(restoreLatestBackup)))
        toolbar.addArrangedSubview(button("Repair Names", #selector(repairNames)))
        toolbar.addArrangedSubview(button("Export Config", #selector(exportConfig)))
        toolbar.addArrangedSubview(button("Import Config", #selector(importConfig)))
        let preferencesButton = button("Preferences", #selector(showPreferencesClicked))
        self.preferencesButton = preferencesButton
        toolbar.addArrangedSubview(preferencesButton)
        toolbar.addArrangedSubview(button("Show Overview", #selector(showOverviewClicked)))
        toolbar.addArrangedSubview(button("Show Notes Overlay", #selector(showLabelsClicked)))
        toolbar.addArrangedSubview(button("Assign Visible Apps", #selector(assignVisibleAppsClicked)))
        toolbar.addArrangedSubview(button("Resolve Duplicates", #selector(resolveDuplicateRules)))
        toolbar.addArrangedSubview(button("Switch + Launch", #selector(switchAndLaunchActiveSpace)))
        toolbar.addArrangedSubview(button("Capture Preview", #selector(captureActivePreview)))
        toolbar.addArrangedSubview(button("Test HUD", #selector(testHUD)))
        toolbar.addArrangedSubview(button("Screenshot", #selector(captureScreenshot)))
        toolbar.addArrangedSubview(button("Accessibility...", #selector(requestAccessibility)))
        toolbarScroll.documentView = toolbar

        contentView.addSubview(scroll)
        contentView.addSubview(toolbarScroll)

        NSLayoutConstraint.activate([
            toolbarScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbarScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbarScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            toolbarScroll.heightAnchor.constraint(equalToConstant: 54),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: toolbarScroll.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: toolbarScroll.contentView.leadingAnchor),
            toolbar.topAnchor.constraint(equalTo: toolbarScroll.contentView.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: toolbarScroll.contentView.bottomAnchor),
            scrollDocument.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollDocument.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollDocument.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollDocument.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollDocument.bottomAnchor)
        ])
    }

    private func fitWindowToVisibleScreen() {
        guard let window else { return }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visible else { return }
        let targetWidth = min(max(window.frame.width, 900), visible.width - 80)
        let targetHeight = min(max(window.frame.height, 520), visible.height - 80)
        let origin = NSPoint(
            x: visible.midX - targetWidth / 2,
            y: visible.midY - targetHeight / 2
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: targetWidth, height: targetHeight)), display: true)
    }

    private func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(header())
        let bindings = Dictionary(uniqueKeysWithValues: store.nameBindingSummaries().map { ($0.orderIndex, $0) })
        for space in store.spaces {
            stack.addArrangedSubview(SpaceRowView(
                space: space,
                isActive: space.orderIndex == store.config.lastKnownActiveOrderIndex,
                binding: bindings[space.orderIndex],
                showHUD: { [weak self] space in self?.showHUD(space) },
                switchSpace: { [weak self] space in _ = self?.bridge.switchToSpace(space, from: self?.store.config.lastKnownActiveOrderIndex) },
                switchAndLaunch: { [weak self] space in self?.switchAndLaunch(space) },
                launchApps: { [weak self] space in self?.launchAssignedApps(space) },
                assignVisibleApps: { [weak self] space in self?.assignVisibleApps(to: space) }
            ) { [weak self] updated in
                self?.store.update(updated)
            })
        }
    }

    private func header() -> NSView {
        let snapshot = RuleEngine(store: store, scanner: scanner).snapshot()
        let duplicateCount = snapshot.duplicateAssignments.count
        let summary = [
            "Spaces are visual labels over native macOS Desktops.",
            "Open notes overlay: menu bar badge -> Show Desktop Notes Overlay, or click Show Notes Overlay.",
            "Unassigned visible apps: \(snapshot.unassignedVisibleApps.count)",
            "Duplicate app rules: \(duplicateCount)"
        ].joined(separator: "  ")
        let label = NSTextField(labelWithString: summary)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func refreshSpaces() {
        detector.refresh(reason: "editor refresh")
        reload()
    }

    @objc private func resetNames() {
        store.resetNames()
        reload()
    }

    @objc private func backupConfig() {
        _ = store.createBackup(reason: "manual-editor")
        reload()
    }

    @objc private func restoreLatestBackup() {
        do {
            try store.restoreLatestBackup()
            reload()
        } catch {
            showError(error)
        }
    }

    @objc private func repairNames() {
        let repaired = store.repairOrderFallbackNamesFromHistory()
        AppLog.shared.info(repaired.isEmpty ? "No order-fallback Space names needed repair." : "Repaired \(repaired.count) Space name(s) from stable history.")
        reload()
    }

    @objc private func requestAccessibility() {
        scanner.requestAccessibilityIfNeeded()
    }

    @objc private func showOverviewClicked() {
        showOverview()
    }

    @objc private func showLabelsClicked() {
        showLabelOverlay()
    }

    @objc private func assignVisibleAppsClicked() {
        let active = store.config.lastKnownActiveOrderIndex
        assignVisibleApps(to: store.space(orderIndex: active))
    }

    @objc private func resolveDuplicateRules() {
        let resolved = RuleEngine(store: store, scanner: scanner).resolveDuplicateAssignments()
        AppLog.shared.info(resolved.isEmpty ? "No duplicate app rules to resolve." : "Resolved \(resolved.count) duplicate app rule(s).")
        reload()
    }

    @objc private func switchAndLaunchActiveSpace() {
        switchAndLaunch(store.space(orderIndex: store.config.lastKnownActiveOrderIndex))
    }

    @objc private func captureActivePreview() {
        previewService.capturePreview(for: store.space(orderIndex: store.config.lastKnownActiveOrderIndex))
        reload()
    }

    @objc private func showPreferencesClicked() {
        showPreferences()
    }

    func isPreferencesInteraction(at screenPoint: NSPoint) -> Bool {
        guard let window, let preferencesButton else { return false }
        let bounds = preferencesButton.bounds.intersection(preferencesButton.visibleRect)
        return window.convertToScreen(preferencesButton.convert(bounds, to: nil)).contains(screenPoint)
    }

    @objc private func testHUD() {
        showHUD(store.space(orderIndex: store.config.lastKnownActiveOrderIndex))
    }

    @objc private func captureScreenshot() {
        do {
            guard screenshotService.requestScreenCaptureIfNeeded() else {
                AppLog.shared.warning("Screen Recording permission requested; screenshot capture postponed")
                return
            }
            let urls = try screenshotService.captureScreens()
            AppLog.shared.info("Captured \(urls.count) screenshot(s)")
        } catch {
            showError(error)
        }
    }

    @objc private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "spaces-config.json"
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try self?.store.exportConfig(to: url) } catch { self?.showError(error) }
        }
    }

    @objc private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.store.importConfig(from: url)
                self.reload()
            } catch {
                self.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window!)
    }

    private func switchAndLaunch(_ space: SpaceMetadata) {
        let switched = bridge.switchToSpace(space, from: store.config.lastKnownActiveOrderIndex)
        guard switched else {
            AppLog.shared.warning("Switch + Launch stopped before launching apps: \(bridge.lastSwitchAttempt)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let results = self.appLaunchService.launchAssignedApps(for: space)
            AppLog.shared.info("Switch + Launch for Desktop \(space.orderIndex): \(results.map(\.message).joined(separator: " "))")
        }
    }

    private func launchAssignedApps(_ space: SpaceMetadata) {
        let results = appLaunchService.launchAssignedApps(for: space)
        AppLog.shared.info("Launch Apps for Desktop \(space.orderIndex): \(results.map(\.message).joined(separator: " "))")
    }

    private func assignVisibleApps(to space: SpaceMetadata) {
        let added = RuleEngine(store: store, scanner: scanner).assignUnassignedVisibleApps(to: space.orderIndex)
        AppLog.shared.info(added.isEmpty ? "No unassigned visible apps to add to Desktop \(space.orderIndex)." : "Added \(added.count) app rule(s) to Desktop \(space.orderIndex).")
        reload()
    }
}

private final class SpaceRowView: NSView {
    private var space: SpaceMetadata
    private let isActive: Bool
    private let binding: SpaceNameBindingSummary?
    private let showHUD: (SpaceMetadata) -> Void
    private let switchSpace: (SpaceMetadata) -> Void
    private let switchAndLaunch: (SpaceMetadata) -> Void
    private let launchApps: (SpaceMetadata) -> Void
    private let assignVisibleApps: (SpaceMetadata) -> Void
    private let onChange: (SpaceMetadata) -> Void

    init(
        space: SpaceMetadata,
        isActive: Bool,
        binding: SpaceNameBindingSummary?,
        showHUD: @escaping (SpaceMetadata) -> Void,
        switchSpace: @escaping (SpaceMetadata) -> Void,
        switchAndLaunch: @escaping (SpaceMetadata) -> Void,
        launchApps: @escaping (SpaceMetadata) -> Void,
        assignVisibleApps: @escaping (SpaceMetadata) -> Void,
        onChange: @escaping (SpaceMetadata) -> Void
    ) {
        self.space = space
        self.isActive = isActive
        self.binding = binding
        self.showHUD = showHUD
        self.switchSpace = switchSpace
        self.switchAndLaunch = switchAndLaunch
        self.launchApps = launchApps
        self.assignVisibleApps = assignVisibleApps
        self.onChange = onChange
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = isActive ? 3 : 1
        layer?.borderColor = (isActive ? NSColor(hex: space.colorHex) : NSColor.separatorColor).cgColor

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let desktop = NSTextField(labelWithString: isActive ? "\(space.desktopLabel) active" : space.desktopLabel)
        desktop.font = .systemFont(ofSize: 13, weight: isActive ? .semibold : .regular)
        desktop.textColor = isActive ? NSColor(hex: space.colorHex) : .labelColor
        desktop.widthAnchor.constraint(equalToConstant: 118).isActive = true
        desktop.toolTip = bindingTooltip()

        let icon = textField(space.icon, placeholder: "Icon", width: 52, action: #selector(iconChanged(_:)))
        let name = textField(space.name, placeholder: "Name", width: 250, action: #selector(nameChanged(_:)))
        let note = textField(space.note, placeholder: "What belongs on this Desktop?", width: 420, action: #selector(noteChanged(_:)))
        let shortcut = textField(space.shortcut, placeholder: "Control+1", width: 150, action: #selector(shortcutChanged(_:)))
        let apps = textField(space.assignedApps.joined(separator: ", "), placeholder: "Suggested apps", width: 300, action: #selector(appsChanged(_:)))
        let color = NSColorWell()
        color.color = NSColor(hex: space.colorHex)
        color.target = self
        color.action = #selector(colorChanged(_:))

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 10

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6
        actions.addArrangedSubview(actionButton("HUD", #selector(showHUDClicked)))
        actions.addArrangedSubview(actionButton("Switch", #selector(switchClicked)))
        actions.addArrangedSubview(actionButton("Assign Visible", #selector(assignVisibleClicked)))
        actions.addArrangedSubview(actionButton("Launch Apps", #selector(launchAppsClicked)))
        actions.addArrangedSubview(actionButton("Switch + Launch", #selector(switchAndLaunchClicked)))

        topRow.addArrangedSubview(desktop)
        topRow.addArrangedSubview(bindingBadge())
        topRow.addArrangedSubview(labeledField("Icon", icon))
        topRow.addArrangedSubview(labeledField("Name", name))
        topRow.addArrangedSubview(color)
        topRow.addArrangedSubview(spacer)
        topRow.addArrangedSubview(actions)

        let detailsRow = NSStackView()
        detailsRow.orientation = .horizontal
        detailsRow.alignment = .top
        detailsRow.spacing = 10
        detailsRow.addArrangedSubview(labeledField("Desktop note", note))
        detailsRow.addArrangedSubview(labeledField("Switch shortcut", shortcut))
        detailsRow.addArrangedSubview(labeledField("Suggested apps", apps))

        root.addArrangedSubview(topRow)
        root.addArrangedSubview(detailsRow)
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            topRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            detailsRow.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor)
        ])
    }

    private func textField(_ value: String, placeholder: String, width: CGFloat, action: Selector) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.target = self
        field.action = action
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    private func labeledField(_ label: String, _ field: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3

        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .secondaryLabelColor
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(field)
        return stack
    }

    private func actionButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func bindingBadge() -> NSTextField {
        let text: String
        let color: NSColor
        if let binding {
            text = binding.mode == .stableID ? "ID" : "Order"
            color = binding.mode == .stableID ? .systemGreen : .systemOrange
        } else {
            text = "?"
            color = .tertiaryLabelColor
        }
        let badge = NSTextField(labelWithString: text)
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = color
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = color.withAlphaComponent(0.7).cgColor
        badge.widthAnchor.constraint(equalToConstant: 48).isActive = true
        badge.toolTip = bindingTooltip()
        return badge
    }

    private func bindingTooltip() -> String {
        guard let binding else { return "Name binding status unavailable." }
        let repair = binding.repairCandidateName.map { " Repair can restore '\($0)' if this row is using an automatic fallback name." } ?? ""
        return "\(binding.mode.label). Remembered stable IDs for this order: \(binding.rememberedStableIDCount).\(repair)"
    }

    @objc private func iconChanged(_ sender: NSTextField) {
        space.icon = sender.stringValue
        onChange(space)
    }

    @objc private func nameChanged(_ sender: NSTextField) {
        space.name = sender.stringValue
        onChange(space)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        space.colorHex = sender.color.hexString
        onChange(space)
    }

    @objc private func noteChanged(_ sender: NSTextField) {
        space.note = sender.stringValue
        onChange(space)
    }

    @objc private func shortcutChanged(_ sender: NSTextField) {
        space.shortcut = sender.stringValue
        onChange(space)
    }

    @objc private func appsChanged(_ sender: NSTextField) {
        space.assignedApps = sender.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        onChange(space)
    }

    @objc private func showHUDClicked() {
        showHUD(space)
    }

    @objc private func switchClicked() {
        switchSpace(space)
    }

    @objc private func switchAndLaunchClicked() {
        switchAndLaunch(space)
    }

    @objc private func launchAppsClicked() {
        launchApps(space)
    }

    @objc private func assignVisibleClicked() {
        assignVisibleApps(space)
    }
}
