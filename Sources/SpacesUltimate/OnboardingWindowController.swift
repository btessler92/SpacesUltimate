import AppKit

final class OnboardingWindowController: NSWindowController {
    private let store: SpaceStore
    private let scanner: WindowScanner
    private let showEditor: () -> Void
    private let showPreferences: () -> Void

    init(
        store: SpaceStore,
        scanner: WindowScanner,
        showEditor: @escaping () -> Void,
        showPreferences: @escaping () -> Void
    ) {
        self.store = store
        self.scanner = scanner
        self.showEditor = showEditor
        self.showPreferences = showPreferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to SpacesUltimate"
        window.center()
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func build() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        let title = NSTextField(labelWithString: "SpacesUltimate labels native macOS Spaces without replacing them.")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.maximumNumberOfLines = 2
        stack.addArrangedSubview(title)

        let body = NSTextField(labelWithString: """
        Start by naming your Desktops, then enable only the permissions and automation you want. Switching uses macOS Control-number Desktop shortcuts when available.
        """)
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 3
        stack.addArrangedSubview(body)

        stack.addArrangedSubview(step("1. Name Spaces", detail: "Open the Space editor and assign names, colors, icons, and app suggestions.", buttonTitle: "Open Editor", action: #selector(openEditorClicked)))
        stack.addArrangedSubview(step("2. Optional Permissions", detail: "Accessibility enables the global overview hotkey and richer app observation.", buttonTitle: "Request Accessibility", action: #selector(accessibilityClicked)))
        stack.addArrangedSubview(step("3. Optional Switching", detail: "Enable macOS shortcuts for switching to Desktop 1, Desktop 2, and so on.", buttonTitle: "Open Keyboard Settings", action: #selector(keyboardSettingsClicked)))
        stack.addArrangedSubview(step("4. Preferences", detail: "Adjust HUD duration, API availability, and global hotkey behavior.", buttonTitle: "Open Preferences", action: #selector(preferencesClicked)))

        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.bezelStyle = .rounded
        stack.addArrangedSubview(done)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    private func step(_ title: String, detail: String, buttonTitle: String, action: Selector) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        let detailField = NSTextField(labelWithString: detail)
        detailField.textColor = .secondaryLabelColor
        detailField.maximumNumberOfLines = 2

        textStack.addArrangedSubview(titleField)
        textStack.addArrangedSubview(detailField)

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(equalToConstant: 170).isActive = true

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(button)
        textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        return row
    }

    @objc private func openEditorClicked() {
        showEditor()
    }

    @objc private func accessibilityClicked() {
        scanner.requestAccessibilityIfNeeded()
    }

    @objc private func keyboardSettingsClicked() {
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func preferencesClicked() {
        showPreferences()
    }

    @objc private func doneClicked() {
        var settings = store.config.settings
        settings.onboardingCompleted = true
        store.updateSettings(settings)
        window?.close()
    }
}
