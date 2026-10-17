import AppKit

final class DebugWindowController: NSWindowController {
    private let store: SpaceStore
    private let detector: SpaceDetector
    private let scanner: WindowScanner
    private let bridge: NativeBridge
    private let ruleEngine: RuleEngine
    private let diagnosticsService: DiagnosticsService
    private let textView = NSTextView()
    private let showHUD: () -> Void
    private let showOverview: () -> Void
    private let hideOverview: () -> Void
    private let switchActiveSpace: () -> Void

    init(
        store: SpaceStore,
        detector: SpaceDetector,
        scanner: WindowScanner,
        bridge: NativeBridge,
        ruleEngine: RuleEngine,
        diagnosticsService: DiagnosticsService,
        showHUD: @escaping () -> Void,
        showOverview: @escaping () -> Void,
        hideOverview: @escaping () -> Void,
        switchActiveSpace: @escaping () -> Void
    ) {
        self.store = store
        self.detector = detector
        self.scanner = scanner
        self.bridge = bridge
        self.ruleEngine = ruleEngine
        self.diagnosticsService = diagnosticsService
        self.showHUD = showHUD
        self.showOverview = showOverview
        self.hideOverview = hideOverview
        self.switchActiveSpace = switchActiveSpace
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpacesUltimate Debug"
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
    }

    func reloadIfVisible() {
        guard window?.isVisible == true else { return }
        reload()
    }

    func reload() {
        let ruleSnapshot = ruleEngine.snapshot()
        let detectionDetails = detector.lastSnapshot.map { Self.detectionDetailsText($0.diagnostics) } ?? "No detection diagnostics yet."
        let displayDetails = detector.lastSnapshot.map { Self.displayDetailsText($0.displayResolutions) } ?? "No display resolutions yet."
        textView.string = """
        Active Space: \(store.config.lastKnownActiveOrderIndex)
        Detection Source: \(detector.lastSnapshot?.source ?? "none")
        Last Detection Event: \(detector.lastSnapshot?.eventDescription ?? "no detection snapshot yet")
        Last Detection Time: \(detector.lastSnapshot.map { Self.dateFormatter.string(from: $0.date) } ?? "n/a")
        Detection Details:
        \(detectionDetails)
        Display Detection:
        \(displayDetails)
        Known Spaces: \(store.spaces.count)
        Accessibility Trusted: \(scanner.isAccessibilityTrusted ? "yes" : "no")
        Screen Recording Trusted: \(diagnosticsService.isScreenCaptureTrusted ? "yes" : "no")
        Permission Target: \(AppIdentity.permissionTargetSummary)
        Config: \(store.configURL.path)
        Backups: \(store.backupsDirectory.path) (\(store.listBackups().count))
        Invalid Configs: \(store.invalidConfigDirectory.path) (\(store.listInvalidConfigs().count))
        Diagnostics: \(diagnosticsService.diagnosticsDirectory.path)
        Control API: http://127.0.0.1:37655/status
        Last Switching Attempt: \(bridge.lastSwitchAttempt)

        Spaces:
        \(store.spaces.map { "- \($0.desktopLabel): \($0.displayName), id=\($0.stableID ?? "order fallback"), color=\($0.colorHex), apps=\($0.assignedApps.joined(separator: ","))" }.joined(separator: "\n"))

        Name Bindings:
        \(store.nameBindingSummaries().map { "- Desktop \($0.orderIndex): \($0.mode.label), remembered=\($0.rememberedStableIDCount), repair=\($0.repairCandidateName ?? "none")" }.joined(separator: "\n"))

        Visible Windows:
        \(scanner.scanVisibleWindows().prefix(20).map { "- \($0.appName): \($0.title)" }.joined(separator: "\n"))

        Rule Suggestions:
        \(ruleSnapshot.matches.isEmpty ? "- No visible apps currently match a Space rule." : ruleSnapshot.matches.map { "- \($0.appName) -> Desktop \($0.spaceOrderIndex) (\($0.spaceName)), windows=\($0.windowCount)" }.joined(separator: "\n"))

        Unassigned Visible Apps:
        \(ruleSnapshot.unassignedVisibleApps.prefix(20).map { "- \($0)" }.joined(separator: "\n"))

        Duplicate Rule Assignments:
        \(ruleSnapshot.duplicateAssignments.isEmpty ? "- none" : ruleSnapshot.duplicateAssignments.map { "- \($0.key): \($0.value.map(String.init).joined(separator: ","))" }.sorted().joined(separator: "\n"))

        Recent Logs:
        \(AppLog.shared.recentMessages.suffix(80).joined(separator: "\n"))
        """
    }

    private func build() {
        guard let contentView = window?.contentView else { return }
        let toolbar = NSStackView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 8, right: 10)
        toolbar.addArrangedSubview(button("Refresh", #selector(refreshClicked)))
        toolbar.addArrangedSubview(button("HUD", #selector(hudClicked)))
        toolbar.addArrangedSubview(button("Show Overview", #selector(showOverviewClicked)))
        toolbar.addArrangedSubview(button("Hide Overview", #selector(hideOverviewClicked)))
        toolbar.addArrangedSubview(button("Switch Active", #selector(switchActiveClicked)))
        toolbar.addArrangedSubview(button("API Status", #selector(apiStatusClicked)))
        toolbar.addArrangedSubview(button("Export Diagnostics", #selector(exportDiagnosticsClicked)))
        toolbar.addArrangedSubview(button("Record Ground Truth", #selector(recordGroundTruthClicked)))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scroll.documentView = textView
        contentView.addSubview(toolbar)
        contentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func refreshClicked() {
        detector.refresh(reason: "debug virtual button")
        reload()
    }

    @objc private func hudClicked() {
        showHUD()
        reload()
    }

    @objc private func showOverviewClicked() {
        showOverview()
        reload()
    }

    @objc private func hideOverviewClicked() {
        hideOverview()
        reload()
    }

    @objc private func switchActiveClicked() {
        switchActiveSpace()
        reload()
    }

    @objc private func apiStatusClicked() {
        let url = URL(string: "http://127.0.0.1:37655/status")!
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        AppLog.shared.info("Copied Control API status URL to clipboard: \(url.absoluteString)")
        reload()
    }

    @objc private func exportDiagnosticsClicked() {
        do {
            let url = try diagnosticsService.exportDiagnostics()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        } catch {
            AppLog.shared.error("Diagnostics export failed: \(error.localizedDescription)")
            showError(error)
        }
        reload()
    }

    @objc private func recordGroundTruthClicked() {
        Task { @MainActor in
            do {
                let url = try await diagnosticsService.exportGroundTruthTimeline()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            } catch {
                AppLog.shared.error("Ground truth export failed: \(error.localizedDescription)")
                showError(error)
            }
            reload()
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Diagnostics export failed"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private static func detectionDetailsText(_ details: SpaceDetectionDiagnostics) -> String {
        let candidates = details.windowMatchCandidates.isEmpty
            ? "none"
            : details.windowMatchCandidates
                .map { "Desktop \($0.orderIndex): \($0.matchedVisibleWindowCount)/\($0.knownWindowCount) visible-window matches" }
                .joined(separator: "; ")
        let notes = details.notes.isEmpty ? "none" : details.notes.joined(separator: " ")
        return """
        - Confidence: \(details.confidence.rawValue)
        - Dock: spaces=\(details.dockSpaceCount), monitors=\(details.dockMonitorCount), current=\(details.dockCurrentStableID ?? "none"), allCurrent=\(details.dockCurrentStableIDs.joined(separator: ","))
        - Window IDs: visible=\(details.visibleWindowIDCount), unique=\(details.uniqueVisibleWindowIDCount), sharedIgnored=\(details.ignoredSharedVisibleWindowIDCount), spaceProperties=\(details.spaceWindowPropertyCount)
        - Resolved: dock=\(details.dockActiveOrderIndex.map(String.init) ?? "none"), windows=\(details.windowMatchedOrderIndex.map(String.init) ?? "none")
        - Window Candidates: \(candidates)
        - Notes: \(notes)
        """
    }

    private static func displayDetailsText(_ resolutions: [SpaceDisplayResolution]) -> String {
        guard !resolutions.isEmpty else {
            return "- none"
        }
        return resolutions.map { resolution in
            let identifier = resolution.dockDisplayIdentifier ?? "unknown"
            let displayID = resolution.displayID.map(String.init) ?? "unmatched"
            let screen = resolution.screenName ?? "unknown screen"
            let current = resolution.dockCurrentStableID ?? "none"
            let dock = resolution.dockResolvedOrderIndex.map(String.init) ?? "none"
            let window = resolution.windowMatchedOrderIndex.map(String.init) ?? "none"
            let active = resolution.resolvedOrderIndex.map(String.init) ?? "none"
            let uiTarget = resolution.resolvedOrderIndex.map { "Desktop \($0)" } ?? "none"
            return "- \(screen) id=\(displayID), match=\(resolution.screenMatch), confidence=\(resolution.confidence.rawValue), source=\(resolution.source), dockIdentifier=\(identifier), current=\(current), dockDesktop=\(dock), windowDesktop=\(window), activeDesktop=\(active), uiTarget=\(uiTarget), visibleWindows=\(resolution.visibleWindowIDCount)"
        }.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
