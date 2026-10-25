import AppKit

final class InlineEditableNameField: NSTextField, NSTextFieldDelegate {
    private let displayText: (String) -> String
    private let onCommit: (String) -> Void
    private var rawValue: String
    private let fallbackName: String
    private var displayColor: NSColor?
    private var isEditingName = false
    var allowsNameEditing = true
    var onBeginEditing: (() -> Void)?
    var onSingleClick: (() -> Void)?

    init(
        name: String,
        fallbackName: String,
        displayText: @escaping (String) -> String = { $0 },
        onCommit: @escaping (String) -> Void
    ) {
        let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : name
        self.rawValue = name
        self.fallbackName = fallbackName
        self.displayText = displayText
        self.onCommit = onCommit
        super.init(frame: .zero)
        stringValue = displayText(initial)
        delegate = self
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        toolTip = "Double-click to rename this Desktop"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            beginNameEditing()
        } else {
            onSingleClick?()
            super.mouseDown(with: event)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitNameEditing()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        commitNameEditing()
    }

    private func beginNameEditing() {
        guard allowsNameEditing, !isEditingName else { return }
        isEditingName = true
        onBeginEditing?()
        displayColor = textColor
        stringValue = rawValue
        placeholderString = fallbackName
        isEditable = true
        isSelectable = true
        isBordered = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .textColor
        focusRingType = .default
        window?.makeKey()
        window?.makeFirstResponder(self)
        currentEditor()?.selectAll(nil)
    }

    private func commitNameEditing() {
        guard isEditingName else { return }
        isEditingName = false
        rawValue = stringValue
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        if let displayColor {
            textColor = displayColor
        }
        let visible = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : rawValue
        stringValue = displayText(visible)
        // Saving may replace the containing view. Finish the field's editing lifecycle first.
        onCommit(rawValue)
    }
}
