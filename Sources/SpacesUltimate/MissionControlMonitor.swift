import AppKit

/// Observes Dock's on-screen windows without intercepting Mission Control shortcuts or gestures.
@MainActor
final class MissionControlMonitor {
    private var timer: Timer?
    private var state = MissionControlSessionState()
    private let onChange: (Bool) -> Void
    private(set) var lastSampleAvailable = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state = MissionControlSessionState()
    }

    func statusPayload() -> [String: Any] {
        [
            "monitoring": timer != nil,
            "active": state.isActive,
            "lastSampleAvailable": lastSampleAvailable,
            "detectionMethod": "Dock full-display window at layer 18",
            "pollIntervalSeconds": 0.25
        ]
    }

    private func sample() {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            lastSampleAvailable = false
            _ = state.observe(nil)
            return
        }
        lastSampleAvailable = true
        let dockPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .map(\.processIdentifier))
        let screenBounds = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            // CGWindow bounds use a top-left origin; NSScreen.frame uses a bottom-left origin.
            return CGDisplayBounds(number.uint32Value)
        }
        let active = MissionControlWindowDetection.isActive(
            windows: windows, dockPIDs: dockPIDs, screenBounds: screenBounds
        )
        guard let changed = state.observe(active, mouseIsPressed: NSEvent.pressedMouseButtons != 0) else { return }
        AppLog.shared.info("Mission Control \(changed ? "opened" : "closed")")
        onChange(changed)
    }
}

enum MissionControlWindowDetection {
    static func isActive(windows: [[String: Any]], dockPIDs: Set<pid_t>, screenBounds: [CGRect]) -> Bool {
        windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
                  dockPIDs.contains(pid.int32Value),
                  window[kCGWindowLayer as String] as? Int == 18,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return false }
            // Empirical Dock signature, verified on macOS 26.6.2. Window names are permission-
            // gated and sharing state varies by OS version, so neither is used for detection.
            return screenBounds.contains { screen in
                abs(bounds.minX - screen.minX) <= 2 && abs(bounds.minY - screen.minY) <= 2
                    && abs(bounds.width - screen.width) <= 2 && abs(bounds.height - screen.height) <= 2
                    && screen.width > 0 && screen.height > 0
            }
        }
    }
}

struct MissionControlSessionState {
    private(set) var isActive = false
    private var inactiveSamples = 0

    /// Emits only edges, so dismissing notes never reopens them in the same session.
    mutating func observe(_ active: Bool?, mouseIsPressed: Bool = false) -> Bool? {
        guard let active else {
            inactiveSamples = 0
            return nil
        }
        if active {
            inactiveSamples = 0
            guard !isActive else { return nil }
            isActive = true
            return true
        }
        guard isActive else { return nil }
        // Dragging between Desktops can temporarily replace Dock's Mission Control windows.
        // Wait until the mouse is released before confirming that the session ended.
        if mouseIsPressed {
            inactiveSamples = 0
            return nil
        }
        inactiveSamples += 1
        // Dock can briefly remove/recreate its windows while switching desktops inside Mission Control.
        guard inactiveSamples >= 2 else { return nil }
        isActive = false
        inactiveSamples = 0
        return false
    }
}
