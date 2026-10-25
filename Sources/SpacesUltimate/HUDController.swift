import AppKit

struct HUDTimeline {
    let fadeIn: TimeInterval
    let hold: TimeInterval
    let fadeOut: TimeInterval

    init(settings: AppSettings) {
        let settings = settings.normalized
        fadeIn = settings.hudFadeInSeconds
        hold = settings.hudHoldSeconds
        fadeOut = settings.hudDurationSeconds
    }

    var duration: TimeInterval { fadeIn + hold + fadeOut }

    func opacity(at elapsed: TimeInterval) -> CGFloat {
        let elapsed = max(0, elapsed)
        func smooth(_ progress: Double) -> CGFloat {
            let value = min(max(progress, 0), 1)
            return CGFloat(value * value * (3 - 2 * value))
        }
        if elapsed < fadeIn { return smooth(elapsed / fadeIn) }
        if elapsed < fadeIn + hold { return 1 }
        return 1 - smooth((elapsed - fadeIn - hold) / fadeOut)
    }
}

enum HUDLayout {
    static func frame(visibleFrame: NSRect, settings: AppSettings) -> NSRect {
        let settings = settings.normalized
        let margin: CGFloat = min(28, max(0, min(visibleFrame.width, visibleFrame.height) / 10))
        let scale = min(CGFloat(settings.hudScale),
                        max(0.01, (visibleFrame.width - margin * 2) / 360),
                        max(0.01, (visibleFrame.height - margin * 2) / 160))
        let size = NSSize(width: 360 * scale, height: 160 * scale)
        var origin = NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        switch settings.hudPosition {
        case .right: origin.x = visibleFrame.maxX - size.width - margin
        case .left: origin.x = visibleFrame.minX + margin
        case .top: origin.y = visibleFrame.maxY - size.height - margin
        case .bottom: origin.y = visibleFrame.minY + margin
        case .center: break
        }
        return NSRect(origin: origin, size: size)
    }
}

@MainActor
final class HUDController {
    private(set) var panels: [NSPanel] = []
    private(set) var generation = 0
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var timeline = HUDTimeline(settings: .defaults)
    private let clock: () -> TimeInterval
    private let present: (NSPanel) -> Void

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         present: @escaping (NSPanel) -> Void = { $0.orderFrontRegardless() }) {
        self.clock = clock
        self.present = present
    }

    func show(space: SpaceMetadata, desktopNumber: Int, settings: AppSettings) {
        show(settings: settings) { _ in (space, desktopNumber) }
    }

    func show(store: SpaceStore, detector: SpaceDetector, settings: AppSettings) {
        show(settings: settings) { screen in
            let resolution = detector.displayResolution(for: screen)
            if let fullscreen = resolution.fullscreenSpace { return (fullscreen, fullscreen.orderIndex) }
            let orderIndex = resolution.resolvedOrderIndex ?? store.config.lastKnownActiveOrderIndex
            return (store.space(orderIndex: orderIndex), orderIndex)
        }
    }

    func hide() {
        generation += 1
        timer?.invalidate()
        timer = nil
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    private func show(settings: AppSettings, content: (NSScreen) -> (SpaceMetadata, Int)) {
        hide()
        timeline = HUDTimeline(settings: settings)
        startedAt = clock()
        panels = NSScreen.screens.map { screen in
            let (space, desktopNumber) = content(screen)
            return makePanel(on: screen, space: space, desktopNumber: desktopNumber, settings: settings)
        }
        panels.forEach {
            $0.alphaValue = timeline.opacity(at: 0)
            present($0)
        }
        let currentGeneration = generation
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceAnimation(generation: currentGeneration) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // A tick queued before another preview must never fade or close the newer HUD.
    func advanceAnimation(generation expectedGeneration: Int) {
        guard expectedGeneration == generation else { return }
        let elapsed = clock() - startedAt
        guard elapsed < timeline.duration else { hide(); return }
        panels.forEach { $0.alphaValue = timeline.opacity(at: elapsed) }
    }

    private func makePanel(on screen: NSScreen, space: SpaceMetadata, desktopNumber: Int, settings: AppSettings) -> NSPanel {
        let frame = HUDLayout.frame(visibleFrame: screen.visibleFrame, settings: settings)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.contentView = HUDView(space: space, desktopNumber: desktopNumber, settings: settings, size: frame.size)
        return panel
    }
}

final class HUDView: NSView {
    private let backgroundOpacity: CGFloat

    init(space: SpaceMetadata, desktopNumber: Int, settings: AppSettings, size: NSSize) {
        let settings = settings.normalized
        backgroundOpacity = CGFloat(settings.hudBackgroundOpacity)
        super.init(frame: NSRect(origin: .zero, size: size))
        let scale = size.width / 360
        wantsLayer = true
        layer?.cornerRadius = 18 * scale
        layer?.borderWidth = 3 * scale
        layer?.borderColor = NSColor(hex: space.colorHex).cgColor
        updateBackground()

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8 * scale

        let title = NSTextField(wrappingLabelWithString: "\(space.icon.isEmpty ? "" : "\(space.icon) ")\(space.displayName)")
        title.font = .systemFont(ofSize: 38 * scale, weight: .bold)
        title.textColor = .labelColor
        title.alignment = .center
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.toolTip = space.displayName
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.widthAnchor.constraint(equalToConstant: size.width - 40 * scale).isActive = true
        stack.addArrangedSubview(title)
        if settings.hudShowsDesktopNumber {
            let subtitle = NSTextField(labelWithString: space.isFullscreen ? "Fullscreen app" : "Desktop \(desktopNumber)")
            subtitle.font = .systemFont(ofSize: 18 * scale, weight: .medium)
            subtitle.textColor = .secondaryLabelColor
            stack.addArrangedSubview(subtitle)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12 * scale),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12 * scale)
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(backgroundOpacity).cgColor
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
