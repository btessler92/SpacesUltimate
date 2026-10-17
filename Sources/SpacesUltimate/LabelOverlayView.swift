import AppKit

private final class SquareNotesNavigationButton: NSButton {
    // AppKit's square bezel adds vertical alignment insets. Use its actual bounds
    // for layout so the visible control and Mission Control hit target stay square.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
}

final class LabelOverlayView: NSView {
    private let spaces: [SpaceMetadata]
    private(set) var activeIndex: Int
    private(set) var itemOpacity: CGFloat
    private(set) var backgroundOpacity: CGFloat
    private let background = NSVisualEffectView()
    private let screenFrame: NSRect
    private let beginEditing: () -> Void
    private let rename: (SpaceMetadata) -> Void
    private let navigate: (SpaceMetadata) -> Void
    private let close: () -> Void
    private let labelWidth: CGFloat
    let presentationLayout: NotesOverlayLayout
    private var cardsByOrderIndex: [Int: NSView] = [:]
    private var navigationButtons: [Int: NSButton] = [:]
    private var closeButton: NSButton?

    init(
        spaces: [SpaceMetadata],
        activeIndex: Int,
        itemOpacity: Double,
        backgroundOpacity: Double = AppSettings.defaults.notesOverlayBackgroundOpacity,
        screenFrame: NSRect,
        presentationLayout: NotesOverlayLayout? = nil,
        beginEditing: @escaping () -> Void,
        rename: @escaping (SpaceMetadata) -> Void,
        navigate: @escaping (SpaceMetadata) -> Void = { _ in },
        close: @escaping () -> Void
    ) {
        self.spaces = spaces
        self.activeIndex = activeIndex
        self.itemOpacity = CGFloat(min(max(itemOpacity, 0.12), 0.90))
        self.backgroundOpacity = CGFloat(min(max(backgroundOpacity, 0), 1))
        self.screenFrame = screenFrame
        self.beginEditing = beginEditing
        self.rename = rename
        self.navigate = navigate
        self.close = close
        let layout = presentationLayout ?? NotesOverlayLayout(spaces: spaces, availableWidth: screenFrame.width)
        self.presentationLayout = layout
        self.labelWidth = layout.labelWidth
        super.init(frame: screenFrame)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    var cardScreenFrames: [NSRect] {
        guard let window else { return [] }
        layoutSubtreeIfNeeded()
        return cardsByOrderIndex.values.compactMap { card in
            let visible = card.bounds.intersection(card.visibleRect)
            guard !visible.isEmpty else { return nil }
            return window.convertToScreen(card.convert(visible, to: nil))
        }
    }

    func containsCardOrNavigationButton(at screenPoint: NSPoint) -> Bool {
        cardScreenFrames.contains { $0.contains(screenPoint) } || navigationTarget(at: screenPoint) != nil
    }

    func navigationTarget(at screenPoint: NSPoint) -> (space: SpaceMetadata, frame: NSRect)? {
        guard let window else { return nil }
        layoutSubtreeIfNeeded()
        for space in spaces {
            guard let button = navigationButtons[space.orderIndex] else { continue }
            let clickableBounds = button.bounds.intersection(button.visibleRect)
            let frame = window.convertToScreen(button.convert(clickableBounds, to: nil))
            if frame.contains(screenPoint) { return (space, frame) }
        }
        return nil
    }

    func isCloseButton(at screenPoint: NSPoint) -> Bool {
        guard let window, let closeButton else { return false }
        layoutSubtreeIfNeeded()
        let clickableBounds = closeButton.bounds.intersection(closeButton.visibleRect)
        return window.convertToScreen(closeButton.convert(clickableBounds, to: nil)).contains(screenPoint)
    }

    @objc private func goToDesktop(_ sender: NSButton) {
        guard let space = spaces.first(where: { $0.orderIndex == sender.tag }) else { return }
        beginEditing()
        navigate(space)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    @discardableResult
    func updateActiveIndex(_ orderIndex: Int) -> Bool {
        guard activeIndex != orderIndex else { return false }
        activeIndex = orderIndex
        for space in spaces {
            guard let card = cardsByOrderIndex[space.orderIndex] else { continue }
            updateAppearance(of: card, for: space)
        }
        return true
    }

    private func scaledFontSize(minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        NotesOverlayLayout.scaledFontSize(cardWidth: labelWidth, minimum: minimum, maximum: maximum)
    }

    func updateOpacity(item: Double, background: Double) {
        itemOpacity = CGFloat(min(max(item, 0.12), 0.90))
        backgroundOpacity = CGFloat(min(max(background, 0), 1))
        self.background.alphaValue = backgroundOpacity
        for space in spaces {
            if let card = cardsByOrderIndex[space.orderIndex] { updateAppearance(of: card, for: space) }
        }
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let strip = NSView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.wantsLayer = true
        strip.layer?.cornerRadius = 18
        background.translatesAutoresizingMaskIntoConstraints = false
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.alphaValue = backgroundOpacity
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        background.layer?.shadowColor = NSColor.black.cgColor
        background.layer?.shadowOpacity = 0.14
        background.layer?.shadowRadius = 18
        background.layer?.shadowOffset = NSSize(width: 0, height: -3)

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = NotesOverlayLayout.closeButtonSpacing
        root.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        self.closeButton = closeButton
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .mini
        closeButton.font = .systemFont(ofSize: 10.5, weight: .medium)
        closeButton.widthAnchor.constraint(equalToConstant: NotesOverlayLayout.closeButtonWidth).isActive = true
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .none

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        let cardAreaWidth = max(1, screenFrame.width - NotesOverlayLayout.horizontalInsets
            - NotesOverlayLayout.closeButtonWidth - NotesOverlayLayout.closeButtonSpacing)
        let rowHeight = max(1, (screenFrame.height - NotesOverlayLayout.verticalInsets
            - CGFloat(presentationLayout.rowCount - 1) * NotesOverlayLayout.rowSpacing)
            / CGFloat(presentationLayout.rowCount))
        for (rowIndex, indices) in presentationLayout.rows.enumerated() {
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.wantsLayer = true
            row.layer?.masksToBounds = true
            row.clipsToBounds = true
            document.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: document.trailingAnchor),
                row.topAnchor.constraint(equalTo: document.topAnchor,
                    constant: CGFloat(rowIndex) * (rowHeight + NotesOverlayLayout.rowSpacing)),
                row.heightAnchor.constraint(equalToConstant: rowHeight)
            ])
            let offset = presentationLayout.leadingOffset(for: rowIndex, cardAreaWidth: cardAreaWidth)
            for (column, index) in indices.enumerated() {
                let space = spaces[index]
                let card = label(for: space, rowHeight: rowHeight)
                card.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(card)
                NSLayoutConstraint.activate([
                    card.leadingAnchor.constraint(equalTo: row.leadingAnchor,
                        constant: offset + CGFloat(column) * presentationLayout.cardPitch),
                    card.topAnchor.constraint(equalTo: row.topAnchor)
                ])
            }
        }
        root.addArrangedSubview(scrollView)
        root.addArrangedSubview(closeButton)
        strip.addSubview(background)
        strip.addSubview(root)
        addSubview(strip)

        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: strip.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: strip.trailingAnchor),
            background.topAnchor.constraint(equalTo: strip.topAnchor),
            background.bottomAnchor.constraint(equalTo: strip.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: strip.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: strip.trailingAnchor),
            root.topAnchor.constraint(equalTo: strip.topAnchor),
            root.bottomAnchor.constraint(equalTo: strip.bottomAnchor),
            scrollView.heightAnchor.constraint(equalTo: root.heightAnchor, constant: -NotesOverlayLayout.verticalInsets),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        ])
    }

    @objc private func closeClicked() {
        close()
    }

    private func label(for space: SpaceMetadata, rowHeight: CGFloat) -> NSView {
        let compact = presentationLayout.hasCompactNavigationButton
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = compact ? .leading : .centerX
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: compact ? 3 : 6, left: 10, bottom: compact ? 3 : 6, right: compact ? 6 : 10)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 12
        updateAppearance(of: stack, for: space)
        cardsByOrderIndex[space.orderIndex] = stack
        stack.widthAnchor.constraint(equalToConstant: presentationLayout.cardWidth).isActive = true
        if compact { stack.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true }

        let number = NSTextField(labelWithString: String(space.orderIndex))
        let numberFont = NotesOverlayLayout.numberFont(cardWidth: labelWidth)
        number.font = numberFont
        number.textColor = .labelColor
        number.alignment = .center
        number.toolTip = space.desktopLabel
        number.setAccessibilityLabel(space.desktopLabel)
        number.setContentCompressionResistancePriority(.required, for: .horizontal)
        let numberWidth = NotesOverlayLayout.numberWidth(orderIndex: space.orderIndex, cardWidth: labelWidth)
        number.widthAnchor.constraint(equalToConstant: numberWidth).isActive = true

        // Keep the number beside the text so it stays large in the compact layout too.
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.widthAnchor.constraint(equalToConstant: max(1, labelWidth - 20)).isActive = true
        let textColumn = NSStackView()
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 2
        let textWidth = NotesOverlayLayout.textColumnWidth(orderIndex: space.orderIndex, cardWidth: labelWidth)
        textColumn.widthAnchor.constraint(equalToConstant: textWidth).isActive = true

        let title = InlineEditableNameField(
            name: space.name,
            fallbackName: space.desktopLabel,
            displayText: { [icon = space.icon] name in "\(icon.isEmpty ? "" : "\(icon) ")\(name)" }
        ) { [weak self, space] name in
            var updated = space
            updated.name = name
            self?.rename(updated)
        }
        title.font = NotesOverlayLayout.titleFont(cardWidth: labelWidth)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth).isActive = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.toolTip = "\(space.displayName) — Double-click to rename this Desktop"
        title.onBeginEditing = { [weak self] in self?.beginEditing() }
        title.onSingleClick = { [weak self] in self?.beginEditing() }

        textColumn.addArrangedSubview(title)
        if !compact {
            let button = navigationButton(for: space)
            button.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth).isActive = true
            textColumn.addArrangedSubview(button)
        }
        header.addArrangedSubview(number)
        header.addArrangedSubview(textColumn)
        if compact {
            let button = navigationButton(for: space)
            button.translatesAutoresizingMaskIntoConstraints = false
            stack.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
                button.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: NotesOverlayLayout.navigationButtonSize),
                button.heightAnchor.constraint(equalToConstant: NotesOverlayLayout.navigationButtonSize)
            ])
        }
        stack.addArrangedSubview(header)
        if let note = overlayNote(for: space) {
            let noteField = NSTextField(labelWithString: note)
            noteField.font = .systemFont(ofSize: scaledFontSize(minimum: 9, maximum: compact ? 11 : 12), weight: .regular)
            noteField.textColor = NSColor.labelColor.withAlphaComponent(0.88)
            noteField.alignment = compact ? .left : .center
            let compactSingleLine = compact && rowHeight < 56
            noteField.lineBreakMode = compactSingleLine ? .byTruncatingTail : .byWordWrapping
            noteField.maximumNumberOfLines = compactSingleLine ? 1 : 2
            noteField.toolTip = note
            noteField.widthAnchor.constraint(lessThanOrEqualToConstant: compact ? textWidth : max(44, labelWidth - 28)).isActive = true
            if compact { textColumn.addArrangedSubview(noteField) }
            else { stack.addArrangedSubview(noteField) }
        }
        return stack
    }

    private func navigationButton(for space: SpaceMetadata) -> NSButton {
        let compact = presentationLayout.hasCompactNavigationButton
        let button = compact
            ? SquareNotesNavigationButton(title: "Go", target: self, action: #selector(goToDesktop(_:)))
            : NSButton(title: "Go →", target: self, action: #selector(goToDesktop(_:)))
        button.tag = space.orderIndex
        button.bezelStyle = compact ? .smallSquare : .inline
        button.controlSize = .mini
        button.font = .systemFont(ofSize: compact ? 10 : scaledFontSize(minimum: 8.5, maximum: 11), weight: .medium)
        button.toolTip = "Switch to \(space.displayName)"
        button.setAccessibilityLabel("Go to \(space.desktopLabel): \(space.displayName)")
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        navigationButtons[space.orderIndex] = button
        return button
    }

    private func updateAppearance(of card: NSView, for space: SpaceMetadata) {
        let isActive = space.orderIndex == activeIndex
        card.layer?.backgroundColor = (isActive
            ? NSColor(hex: space.colorHex).withAlphaComponent(itemOpacity)
            : NSColor.controlBackgroundColor.withAlphaComponent(itemOpacity)
        ).cgColor
        card.layer?.borderWidth = isActive ? 2 : 1
        card.layer?.borderColor = NSColor(hex: space.colorHex).cgColor
    }

    private func overlayNote(for space: SpaceMetadata) -> String? {
        let note = space.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : note
    }
}
