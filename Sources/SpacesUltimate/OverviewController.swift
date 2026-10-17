import AppKit

@MainActor
final class OverviewController {
    private let store: SpaceStore
    private let scanner: WindowScanner
    private let bridge: NativeBridge
    private let ruleEngine: RuleEngine
    private let previewService: SpacePreviewService
    private var panels: [NSPanel] = []

    init(store: SpaceStore, scanner: WindowScanner, bridge: NativeBridge, ruleEngine: RuleEngine, previewService: SpacePreviewService) {
        self.store = store
        self.scanner = scanner
        self.bridge = bridge
        self.ruleEngine = ruleEngine
        self.previewService = previewService
    }

    func toggle() {
        if panels.contains(where: \.isVisible) {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panels.contains(where: \.isVisible) {
            panels.forEach { $0.orderFrontRegardless() }
            return
        }
        previewService.capturePreview(for: store.space(orderIndex: store.config.lastKnownActiveOrderIndex))

        let screens = NSScreen.screens.isEmpty ? [nil] : NSScreen.screens.map(Optional.some)
        panels = screens.map { screen in
            let frame = Self.overviewFrame(for: screen)
            let panel = KeyableOverlayPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = OverviewView(store: store, scanner: scanner, bridge: bridge, ruleEngine: ruleEngine, previewService: previewService) { [weak self] in
                self?.hide()
            }
            panel.orderFrontRegardless()
            return panel
        }
        AppLog.shared.info("Showed overview on \(panels.count) display(s).")
    }

    private static func overviewFrame(for screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 760)
        let width = min(1120, max(520, visible.width - 96))
        let height = min(500, max(380, visible.height - 180))
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    func hide() {
        panels.forEach { $0.close() }
        panels = []
    }

    func reload() {
        guard panels.contains(where: \.isVisible) else { return }
        for panel in panels {
            panel.contentView = OverviewView(store: store, scanner: scanner, bridge: bridge, ruleEngine: ruleEngine, previewService: previewService) { [weak self] in
                self?.hide()
            }
        }
    }
}

private final class OverviewView: NSView {
    private let store: SpaceStore
    private let scanner: WindowScanner
    private let bridge: NativeBridge
    private let ruleEngine: RuleEngine
    private let previewService: SpacePreviewService
    private let close: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")

    init(store: SpaceStore, scanner: WindowScanner, bridge: NativeBridge, ruleEngine: RuleEngine, previewService: SpacePreviewService, close: @escaping () -> Void) {
        self.store = store
        self.scanner = scanner
        self.bridge = bridge
        self.ruleEngine = ruleEngine
        self.previewService = previewService
        self.close = close
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 18

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .regular

        header.addArrangedSubview(spacer)
        header.addArrangedSubview(closeButton)
        root.addArrangedSubview(header)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let cards = NSStackView()
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.orientation = .horizontal
        cards.alignment = .top
        cards.distribution = .fill
        cards.spacing = 14

        let windows = scanner.scanVisibleWindows()
        let ruleSnapshot = ruleEngine.snapshot(for: windows)
        for space in store.spaces {
            let matches = ruleSnapshot.matches.filter { $0.spaceOrderIndex == space.orderIndex }
            cards.addArrangedSubview(SpaceCardView(
                space: space,
                activeIndex: store.config.lastKnownActiveOrderIndex,
                windows: windows,
                ruleMatches: matches,
                previewInfo: previewService.existingPreviewInfo(for: space),
                rename: { [weak self] updated in
                    self?.store.update(updated)
                }
            ) { [weak self] selected in
                guard let self else { return }
                let switched = self.bridge.switchToSpace(selected, from: self.store.config.lastKnownActiveOrderIndex)
                if switched {
                    self.close()
                } else {
                    self.statusLabel.stringValue = self.bridge.lastSwitchAttempt
                    self.statusLabel.isHidden = false
                    AppLog.shared.warning("Overview switch failed: \(self.bridge.lastSwitchAttempt)")
                }
            })
        }

        scrollView.documentView = cards
        root.addArrangedSubview(scrollView)
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = NSColor.systemYellow
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.isHidden = true
        root.addArrangedSubview(statusLabel)
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 365),
            cards.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            cards.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            cards.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor)
        ])
    }

    @objc private func closeClicked() {
        close()
    }
}

private final class SpaceCardView: NSView {
    private let space: SpaceMetadata
    private let activeIndex: Int
    private let actionHandler: (SpaceMetadata) -> Void
    private var pendingClick: DispatchWorkItem?

    init(
        space: SpaceMetadata,
        activeIndex: Int,
        windows: [ScannedWindow],
        ruleMatches: [RuleMatch],
        previewInfo: SpacePreviewService.PreviewInfo?,
        rename: @escaping (SpaceMetadata) -> Void,
        actionHandler: @escaping (SpaceMetadata) -> Void
    ) {
        self.space = space
        self.activeIndex = activeIndex
        self.actionHandler = actionHandler
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = activeIndex == space.orderIndex ? 4 : 1
        layer?.borderColor = NSColor(hex: space.colorHex).cgColor
        widthAnchor.constraint(equalToConstant: 230).isActive = true
        heightAnchor.constraint(equalToConstant: 350).isActive = true
        build(windows: windows, ruleMatches: ruleMatches, previewInfo: previewInfo, rename: rename)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            cancelPendingClick()
            return
        }
        scheduleClick()
    }

    private func scheduleClick() {
        pendingClick?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.actionHandler(self.space)
            self.pendingClick = nil
        }
        pendingClick = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: workItem)
    }

    private func cancelPendingClick() {
        pendingClick?.cancel()
        pendingClick = nil
    }

    private func build(
        windows: [ScannedWindow],
        ruleMatches: [RuleMatch],
        previewInfo: SpacePreviewService.PreviewInfo?,
        rename: @escaping (SpaceMetadata) -> Void
    ) {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        let label = InlineEditableNameField(
            name: space.name,
            fallbackName: space.desktopLabel,
            displayText: { [icon = space.icon] name in "\(icon.isEmpty ? "" : "\(icon) ")\(name)" }
        ) { [space] name in
            var updated = space
            updated.name = name
            rename(updated)
        }
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = NSColor(hex: space.colorHex)
        label.lineBreakMode = .byTruncatingTail
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 198).isActive = true
        label.onSingleClick = { [weak self] in self?.scheduleClick() }
        label.onBeginEditing = { [weak self] in self?.cancelPendingClick() }

        let desktop = NSTextField(labelWithString: space.desktopLabel)
        desktop.font = .systemFont(ofSize: 13, weight: .medium)
        desktop.textColor = .secondaryLabelColor

        let ruleText = space.assignedApps.isEmpty ? "No app rules" : "Rules: \(space.assignedApps.joined(separator: ", "))"
        let rules = NSTextField(labelWithString: ruleText)
        rules.font = .systemFont(ofSize: 12)
        rules.textColor = .tertiaryLabelColor
        rules.maximumNumberOfLines = 3

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(desktop)
        if let note = desktopNote() {
            stack.addArrangedSubview(noteView(note))
        }
        stack.addArrangedSubview(primaryPreviewView(windows: windows, previewInfo: previewInfo))
        stack.addArrangedSubview(rules)
        if !ruleMatches.isEmpty {
            let suggestionText = "Visible rule matches: " + ruleMatches
                .map { "\($0.appName) (\($0.windowCount))" }
                .joined(separator: ", ")
            let suggestions = NSTextField(labelWithString: suggestionText)
            suggestions.font = .systemFont(ofSize: 12, weight: .medium)
            suggestions.textColor = NSColor(hex: space.colorHex)
            suggestions.maximumNumberOfLines = 2
            suggestions.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(suggestions)
        }
        stack.addArrangedSubview(separator())

        let relevantWindows = windowsForCard(windows)
        let windowTitle = NSTextField(labelWithString: relevantWindows.isEmpty ? "Current-space windows unavailable" : "Visible windows")
        windowTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        windowTitle.textColor = .secondaryLabelColor
        windowTitle.lineBreakMode = .byTruncatingTail
        windowTitle.maximumNumberOfLines = 1
        stack.addArrangedSubview(windowTitle)

        for window in relevantWindows.prefix(8) {
            let text = window.title.isEmpty ? window.appName : "\(window.appName): \(window.title)"
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 12)
            field.textColor = .labelColor
            field.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(field)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func windowsForCard(_ windows: [ScannedWindow]) -> [ScannedWindow] {
        if space.orderIndex == activeIndex {
            return windows
        }
        let assigned = Set(space.assignedApps.map { $0.lowercased() })
        guard !assigned.isEmpty else { return [] }
        return windows.filter { assigned.contains($0.appName.lowercased()) }
    }

    private func desktopNote() -> String? {
        let note = space.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : note
    }

    private func noteView(_ note: String) -> NSView {
        let field = NSTextField(labelWithString: note)
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.textColor = .labelColor
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 3
        field.wantsLayer = true
        field.layer?.cornerRadius = 7
        field.layer?.backgroundColor = NSColor(hex: space.colorHex).withAlphaComponent(0.12).cgColor
        return field
    }

    private func primaryPreviewView(windows: [ScannedWindow], previewInfo: SpacePreviewService.PreviewInfo?) -> NSView {
        if space.orderIndex == activeIndex, !windows.isEmpty {
            return WindowMiniMapView(windows: windows)
        }
        return previewView(previewInfo)
    }

    private func previewView(_ info: SpacePreviewService.PreviewInfo?) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        container.heightAnchor.constraint(equalToConstant: 76).isActive = true

        if let info, let image = NSImage(contentsOf: info.url) {
            let imageView = NSImageView(image: image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 8
            imageView.layer?.masksToBounds = true
            container.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            if let modifiedAt = info.modifiedAt {
                let badge = NSTextField(labelWithString: Self.relativePreviewAge(from: modifiedAt))
                badge.translatesAutoresizingMaskIntoConstraints = false
                badge.font = .systemFont(ofSize: 10, weight: .semibold)
                badge.textColor = .white
                badge.wantsLayer = true
                badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
                badge.layer?.cornerRadius = 5
                container.addSubview(badge)
                NSLayoutConstraint.activate([
                    badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                    badge.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
                ])
            }
        } else {
            let label = NSTextField(labelWithString: "No preview captured yet")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .tertiaryLabelColor
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
        }

        return container
    }

    private static func relativePreviewAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    private func separator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.cgColor
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

}

private final class WindowMiniMapView: NSView {
    private let windows: [ScannedWindow]

    init(windows: [ScannedWindow]) {
        self.windows = windows.filter { $0.bounds.width > 40 && $0.bounds.height > 40 }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        heightAnchor.constraint(equalToConstant: 88).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !windows.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }

        let drawingBounds = bounds.insetBy(dx: 10, dy: 10)
        let union = windows.reduce(windows[0].bounds) { $0.union($1.bounds) }
        guard union.width > 0, union.height > 0 else { return }

        let scale = min(drawingBounds.width / union.width, drawingBounds.height / union.height)
        let contentWidth = union.width * scale
        let contentHeight = union.height * scale
        let offsetX = drawingBounds.minX + (drawingBounds.width - contentWidth) / 2
        let offsetY = drawingBounds.minY + (drawingBounds.height - contentHeight) / 2

        for window in windows.prefix(12) {
            let rect = CGRect(
                x: offsetX + (window.bounds.minX - union.minX) * scale,
                y: offsetY + (union.maxY - window.bounds.maxY) * scale,
                width: max(12, window.bounds.width * scale),
                height: max(10, window.bounds.height * scale)
            )
            let color = color(for: window.appName)
            context.setFillColor(color.withAlphaComponent(0.28).cgColor)
            context.setStrokeColor(color.withAlphaComponent(0.95).cgColor)
            let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(path)
            context.drawPath(using: .fillStroke)

            drawLabel(window.appName, in: rect.insetBy(dx: 4, dy: 3))
        }
    }

    private func drawLabel(_ text: String, in rect: CGRect) {
        guard rect.width > 24, rect.height > 12 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func color(for appName: String) -> NSColor {
        let palette: [NSColor] = [.systemBlue, .systemGreen, .systemRed, .systemOrange, .systemPurple, .systemTeal]
        let value = abs(appName.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return palette[value % palette.count]
    }
}
