import AppKit

@MainActor
final class LabelOverlayController {
    private let store: SpaceStore
    private let detector: SpaceDetector
    private let bridge: NativeBridge
    private var panels: [LabelOverlayPanelContext] = []
    private var renderedPresentation: NotesOverlayPresentationFingerprint?
    var retainsNotesForAppMousePress: (NSPoint, Int, NSWindow?) -> Bool = { _, _, _ in false }
    private var dismissWorkItem: DispatchWorkItem?
    private var reloadWorkItem: DispatchWorkItem?
    private var highlightRefreshTimer: Timer?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var lastOutsideMousePress: NotesOverlayMousePress?
    private var interactionState = NotesOverlayInteractionState()
    private var lastDismissalReason = "Overlay has not been dismissed"
    private var systemMouseTimer: Timer?
    private var systemMouseTracking = NotesOverlayMouseTracking()
    private var missionControlIsActive = false
    private var lastMouseObservation = "No click observed"
    private var pendingNavigation: (space: SpaceMetadata, screen: NSScreen, pressID: UInt32, buttonFrame: NSRect)?
    private var lastNavigationPressID: UInt32?
    private var lastNavigationResult = "No navigation requested"
    private var lastHighlightUpdateReason = "Overlay has not been shown"
    private var lastHighlightUpdateDate: Date?
    private lazy var escapeHotKey = GlobalHotKeyController(logName: "notes overlay Escape") { [weak self] in
        self?.hide()
    }

    init(store: SpaceStore, detector: SpaceDetector, bridge: NativeBridge) {
        self.store = store
        self.detector = detector
        self.bridge = bridge
    }

    var isVisible: Bool {
        !panels.isEmpty
    }

    func toggle(duration: TimeInterval = 4.0) {
        if isVisible {
            hide()
        } else {
            show(duration: duration)
        }
    }

    func toggleFromMenuBar() {
        // Outside dismissal runs on mouse-down, while the native status item acts on mouse-up.
        // Match the physical press across both phases and across AppKit/Quartz observation.
        if let event = NSApp.currentEvent,
           lastOutsideMousePress?.matches(button: event.buttonNumber, snapshot: .current()) == true {
            lastOutsideMousePress = nil
            return
        }
        toggle(duration: 0)
    }

    func show(duration: TimeInterval = 4.0, followsMissionControl: Bool = false) {
        hide()
        lastOutsideMousePress = nil
        if followsMissionControl { missionControlIsActive = true }
        interactionState.show(followsMissionControl: followsMissionControl)
        detector.refresh(reason: "notes overlay show")
        rebuildPanels()
        startHighlightRefreshTimer()
        startOutsideClickMonitoring()
        // Mission Control must receive Escape itself; its exit dismisses untouched automatic notes.
        if !missionControlIsActive {
            escapeHotKey.register(shortcut: "Escape")
        }

        if duration > 0 {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.hide() }
            }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
        AppLog.shared.info("Showed Space label overlay on \(panels.count) display(s).")
    }

    private func rebuildPanels() {
        panels.forEach { $0.panel.close() }
        panels = NSScreen.screens.map { screen in
            let summary = detector.notesOverlayDisplaySummary(for: screen)
            let resolution = detector.displayResolution(for: screen)
            let width = NotesOverlayLayout.panelWidth(visibleWidth: screen.visibleFrame.width, spaceCount: summary.spaces.count)
            let layout = NotesOverlayLayout(spaces: summary.spaces, availableWidth: width)
            let frame = layout.panelFrame(visibleFrame: screen.visibleFrame, width: width,
                                          baseHeight: store.config.settings.notesOverlayHeightPixels)
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
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = LabelOverlayView(
                spaces: summary.spaces,
                activeIndex: resolution.resolvedOrderIndex ?? store.config.lastKnownActiveOrderIndex,
                itemOpacity: store.config.settings.notesOverlayItemOpacity,
                backgroundOpacity: store.config.settings.notesOverlayBackgroundOpacity,
                screenFrame: NSRect(origin: .zero, size: frame.size),
                presentationLayout: layout,
                beginEditing: { [weak self] in
                    self?.retainForCardInteraction()
                },
                rename: { [weak self] updated in
                    self?.store.update(updated)
                },
                navigate: { [weak self] space in
                    let event = NSApp.currentEvent
                    let mousePressID = event?.type == .leftMouseUp || event?.type == .leftMouseDown
                        ? NotesOverlayMouseSnapshot.current().downCounts[0] : nil
                    self?.navigate(to: space, on: screen, mousePressID: mousePressID)
                },
                close: { [weak self] in
                    self?.hide()
                }
            )
            panel.orderFrontRegardless()
            return LabelOverlayPanelContext(screen: screen, panel: panel)
        }
        lastHighlightUpdateReason = detector.lastSnapshot?.eventDescription ?? "overlay shown"
        lastHighlightUpdateDate = Date()
        renderedPresentation = NotesOverlayPresentationFingerprint(config: store.config)
    }

    func missionControlDidClose() {
        // Flush counters before deciding whether to dismiss: Dock may have consumed the click
        // without dispatching any NSEvent to this process, even to its global monitor.
        pollSystemMouse()
        missionControlIsActive = false
        guard isVisible else { return }
        if interactionState.shouldDismissOnMissionControlExit {
            hide(reason: "Mission Control exited")
        } else {
            // Clicking a card can itself exit Mission Control. Keep the same panels and editor.
            panels.forEach { $0.panel.orderFrontRegardless() }
            escapeHotKey.register(shortcut: "Escape")
            AppLog.shared.info("Kept notes open after Mission Control exited following a card interaction or manual opening")
            performPendingNavigationIfReady()
        }
    }

    func hide(reason: String = "Explicit dismissal") {
        if isVisible {
            lastDismissalReason = reason
            AppLog.shared.info("Hid notes overlay: \(reason)")
        }
        interactionState.hide()
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        pendingNavigation = nil
        stopOutsideClickMonitoring()
        escapeHotKey.unregister()
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        highlightRefreshTimer?.invalidate()
        highlightRefreshTimer = nil
        panels.forEach { $0.panel.close() }
        panels = []
    }

    func reloadIfVisible() {
        guard !panels.isEmpty else { return }
        let next = NotesOverlayPresentationFingerprint(config: store.config)
        if let renderedPresentation, renderedPresentation.spaces == next.spaces,
           renderedPresentation.heightPixels == next.heightPixels {
            // Slider drags update the existing views, preserving focus and avoiding flicker.
            for context in panels {
                (context.panel.contentView as? LabelOverlayView)?.updateOpacity(
                    item: next.itemOpacity, background: next.backgroundOpacity)
            }
            self.renderedPresentation = next
            return
        }
        // A rename saves synchronously from NSTextField's end-editing notification. Replacing
        // its window inside that notification can interrupt AppKit's field-editor cleanup.
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.reloadWorkItem = nil
                self.rebuildPanels()
            }
        }
        reloadWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func refreshActiveHighlights(reason: String) {
        guard !panels.isEmpty else { return }
        var changedPanels: [String] = []
        for panelIndex in panels.indices {
            let context = panels[panelIndex]
            let resolution = detector.displayResolution(for: context.screen)
            guard let view = context.panel.contentView as? LabelOverlayView else {
                continue
            }
            let activeOrderIndex = panels[panelIndex].highlightPolicy.nextActiveIndex(
                current: view.activeIndex,
                resolved: resolution.resolvedOrderIndex
            )
            guard view.updateActiveIndex(activeOrderIndex) else {
                continue
            }
            changedPanels.append("\(context.screen.localizedName)=Desktop \(activeOrderIndex)")
        }
        guard !changedPanels.isEmpty else { return }
        lastHighlightUpdateReason = reason
        lastHighlightUpdateDate = Date()
        AppLog.shared.info("Updated notes overlay highlight via \(reason): \(changedPanels.joined(separator: ", "))")
    }

    func statusPayload() -> [String: Any] {
        [
            "visible": isVisible,
            "panelCount": panels.count,
            "escapeDismissalRegistered": escapeHotKey.isRegistered,
            "outsideClickMonitoring": localMouseMonitor != nil && globalMouseMonitor != nil,
            "keepsOpenAfterMissionControl": interactionState.keepsOpenAfterMissionControl,
            "lastDismissalReason": lastDismissalReason,
            "systemMouseMonitoring": systemMouseTimer != nil,
            "lastMouseObservation": lastMouseObservation,
            "lastNavigationResult": lastNavigationResult,
            "refreshIntervalSeconds": NotesOverlayLayout.activeHighlightRefreshInterval,
            "lastHighlightUpdateReason": lastHighlightUpdateReason,
            "lastHighlightUpdateDate": lastHighlightUpdateDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "panels": panels.map { context in
                let detectedOrderIndex = detector.displayResolution(for: context.screen).resolvedOrderIndex
                let activeOrderIndex = (context.panel.contentView as? LabelOverlayView)?.activeIndex
                    ?? detectedOrderIndex
                    ?? store.config.lastKnownActiveOrderIndex
                let space = store.space(orderIndex: activeOrderIndex)
                return [
                    "screenName": context.screen.localizedName,
                    "frame": NSStringFromRect(context.panel.frame),
                    "rowCount": (context.panel.contentView as? LabelOverlayView)?.presentationLayout.rowCount ?? 1,
                    "itemOpacity": (context.panel.contentView as? LabelOverlayView)?.itemOpacity ?? 0,
                    "backgroundOpacity": (context.panel.contentView as? LabelOverlayView)?.backgroundOpacity ?? 0,
                    "minimumSingleRowNameFraction": (context.panel.contentView as? LabelOverlayView)?.presentationLayout.minimumSingleRowNameFraction ?? 1,
                    "cardFrames": (context.panel.contentView as? LabelOverlayView)?.cardScreenFrames.map(NSStringFromRect) ?? [],
                    "detectedOrderIndex": detectedOrderIndex ?? NSNull(),
                    "activeOrderIndex": activeOrderIndex,
                    "waitingForResolvedDetection": detectedOrderIndex == nil,
                    "highlightMatchesDetected": detectedOrderIndex.map { activeOrderIndex == $0 } ?? true,
                    "pendingOrderIndex": context.highlightPolicy.pendingIndex ?? NSNull(),
                    "pendingObservations": context.highlightPolicy.pendingObservations,
                    "activeDesktopLabel": space.desktopLabel,
                    "activeDisplayName": space.displayName
                ] as [String: Any]
            }
        ]
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let closedClickedOverlay = MainActor.assumeIsolated {
                guard let self else { return false }
                let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                let clickedOverlay = self.panels.contains { $0.panel === event.window }
                let closed = self.handleMousePress(at: point, button: event.buttonNumber,
                    snapshot: .current(), source: "local", eventWindow: event.window)
                // The overlay window has just closed. Other app windows still receive their click.
                return closed && clickedOverlay
            }
            return closedClickedOverlay ? nil : event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let point: NSPoint
                if let location = event.cgEvent?.location, let mainScreen = NSScreen.screens.first {
                    point = NSPoint(x: location.x, y: mainScreen.frame.maxY - location.y)
                } else {
                    point = NSEvent.mouseLocation
                }
                self.handleMousePress(at: point, button: event.buttonNumber,
                    snapshot: .current(), source: "global")
            }
        }
        systemMouseTracking.synchronize(.current())
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSystemMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        systemMouseTimer = timer
    }

    private func stopOutsideClickMonitoring() {
        systemMouseTimer?.invalidate()
        systemMouseTimer = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    private func pollSystemMouse() {
        guard isVisible, systemMouseTimer != nil else { return }
        let snapshot = NotesOverlayMouseSnapshot.current()
        // Outside Mission Control, AppKit supplies the event's actual location. Quartz only
        // supplies a counter plus the cursor's *current* location, which may already have moved.
        guard missionControlIsActive else {
            systemMouseTracking.synchronize(snapshot)
            performPendingNavigationIfReady()
            return
        }
        let presses = systemMouseTracking.newPresses(in: snapshot)
        if let button = presses.first {
            if handleMousePress(at: NSEvent.mouseLocation, button: button,
                snapshot: snapshot, source: "Quartz activity counter") { return }
        }
        performPendingNavigationIfReady()
    }

    @discardableResult
    private func handleMousePress(at point: NSPoint, button: Int,
                                  snapshot: NotesOverlayMouseSnapshot, source: String, eventWindow: NSWindow? = nil) -> Bool {
        // Ignore synthetic activation events with no valid screen position.
        guard isVisible, isValidMouseLocation(point) else { return false }
        systemMouseTracking.synchronize(snapshot)
        let inside = containsCardOrNavigationButton(at: point)
        recordMouse(at: point, insideCard: inside, source: source)
        if inside {
            retainForCardInteraction()
            if button == 0 { queueMissionControlNavigation(at: point, pressID: snapshot.downCounts[0]) }
            return false
        }
        // Dock may consume the Close button's click too, so handle the explicit dismissal
        // here rather than waiting for an AppKit button action that might never arrive.
        if button == 0, panels.contains(where: {
            ($0.panel.contentView as? LabelOverlayView)?.isCloseButton(at: point) == true
        }) {
            hide(reason: "Close button")
            return true
        }
        pendingNavigation = nil
        if retainsNotesForAppMousePress(point, button, eventWindow) {
            keepVisibleForSettings()
            lastMouseObservation = "\(source): SpacesUltimate settings or menu interaction"
            return false
        }
        guard interactionState.shouldDismissForOutsideClick(missionControlIsActive: missionControlIsActive) else {
            return false
        }
        lastOutsideMousePress = NotesOverlayMousePress(button: button, snapshot: snapshot)
        hide(reason: "Mouse click outside notes cards (\(source))")
        return true
    }

    private func queueMissionControlNavigation(at point: NSPoint, pressID: UInt32) {
        guard missionControlIsActive else { return }
        for context in panels {
            guard let view = context.panel.contentView as? LabelOverlayView,
                  let target = view.navigationTarget(at: point) else { continue }
            pendingNavigation = (target.space, context.screen, pressID, target.frame)
            break
        }
    }

    private func performPendingNavigationIfReady() {
        guard !missionControlIsActive, NSEvent.pressedMouseButtons & 1 == 0,
              let pending = pendingNavigation else { return }
        pendingNavigation = nil
        guard pending.buttonFrame.contains(NSEvent.mouseLocation) else { return }
        navigate(to: pending.space, on: pending.screen, mousePressID: pending.pressID)
    }

    private func recordMouse(at point: NSPoint, insideCard: Bool, source: String) {
        lastMouseObservation = "\(source): \(insideCard ? "card" : "outside") at \(NSStringFromPoint(point))"
        AppLog.shared.info("Notes mouse: \(lastMouseObservation)")
    }

    private func isValidMouseLocation(_ point: NSPoint) -> Bool {
        NotesOverlayMouseLocation.isOnScreen(point, screenFrames: NSScreen.screens.map(\.frame))
    }

    private func navigate(to space: SpaceMetadata, on screen: NSScreen, mousePressID: UInt32?) {
        guard isVisible else { return }
        if let mousePressID, lastNavigationPressID == mousePressID { return }
        lastNavigationPressID = mousePressID
        pendingNavigation = nil
        retainForCardInteraction()
        detector.refresh(reason: "notes Go to Desktop")
        let current = detector.displayResolution(for: screen).resolvedOrderIndex
        if current == space.orderIndex {
            lastNavigationResult = "Already on \(space.desktopLabel)."
            return
        }
        let switched = bridge.switchToSpace(space, from: current)
        lastNavigationResult = bridge.lastSwitchAttempt
        guard !switched else { return }

        // Keep notes available while explaining an actual switching failure.
        stopOutsideClickMonitoring()
        let alert = NSAlert()
        alert.messageText = "Couldn’t switch to \(space.displayName)"
        let needsPermission = !AXIsProcessTrusted()
        alert.informativeText = needsPermission
            ? "Enable SpacesUltimate in System Settings → Privacy & Security → Accessibility to use Go to Desktop."
            : bridge.lastSwitchAttempt
        alert.addButton(withTitle: needsPermission ? "Open Accessibility Settings" : "OK")
        if needsPermission { alert.addButton(withTitle: "Cancel") }
        let response = alert.runModal()
        if needsPermission, response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        if isVisible { startOutsideClickMonitoring() }
    }

    func keepVisibleForSettings() {
        guard isVisible else { return }
        systemMouseTracking.synchronize(.current())
        retainForCardInteraction()
    }

    private func retainForCardInteraction() {
        interactionState.interactWithCard()
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func containsCardOrNavigationButton(at screenPoint: NSPoint) -> Bool {
        panels.contains { context in
            guard let view = context.panel.contentView as? LabelOverlayView else { return false }
            return view.containsCardOrNavigationButton(at: screenPoint)
        }
    }

    private func startHighlightRefreshTimer() {
        highlightRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: NotesOverlayLayout.activeHighlightRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                let reason = "notes overlay live Space poll"
                self.detector.refresh(reason: reason)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        highlightRefreshTimer = timer
    }
}

struct NotesOverlayInteractionState {
    private enum Presentation {
        case hidden, followingMissionControl, interactive
    }
    private var presentation = Presentation.hidden

    var keepsOpenAfterMissionControl: Bool { presentation == .interactive }
    var shouldDismissOnMissionControlExit: Bool { presentation == .followingMissionControl }

    mutating func show(followsMissionControl: Bool) {
        presentation = followsMissionControl ? .followingMissionControl : .interactive
    }

    mutating func interactWithCard() {
        guard presentation != .hidden else { return }
        presentation = .interactive
    }

    mutating func shouldDismissForOutsideClick(missionControlIsActive: Bool) -> Bool {
        guard presentation != .hidden else { return false }
        if missionControlIsActive {
            // An outside action may move a window or rearrange Desktops without exiting
            // Mission Control. Keep notes visible until the session actually ends.
            presentation = .followingMissionControl
            return false
        }
        return true
    }

    mutating func hide() {
        presentation = .hidden
    }
}

struct NotesOverlayPresentationFingerprint: Equatable {
    var spaces: [SpaceMetadata]
    var itemOpacity: Double
    var backgroundOpacity: Double
    var heightPixels: Double

    init(config: SpaceConfig) {
        spaces = config.spaces
        itemOpacity = config.settings.notesOverlayItemOpacity
        backgroundOpacity = config.settings.notesOverlayBackgroundOpacity
        heightPixels = config.settings.notesOverlayHeightPixels
    }
}

struct NotesOverlayHighlightPolicy {
    private(set) var pendingIndex: Int?
    private(set) var pendingObservations = 0

    mutating func nextActiveIndex(current: Int, resolved: Int?) -> Int {
        guard let resolved else {
            clearPendingCandidate()
            return current
        }
        guard resolved != current else {
            clearPendingCandidate()
            return current
        }

        if pendingIndex == resolved {
            pendingObservations += 1
        } else {
            pendingIndex = resolved
            pendingObservations = 1
        }

        guard pendingObservations >= 2 else { return current }
        clearPendingCandidate()
        return resolved
    }

    private mutating func clearPendingCandidate() {
        pendingIndex = nil
        pendingObservations = 0
    }
}

private struct LabelOverlayPanelContext {
    var screen: NSScreen
    var panel: NSPanel
    var highlightPolicy = NotesOverlayHighlightPolicy()
}
