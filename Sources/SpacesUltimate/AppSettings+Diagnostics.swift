import Foundation

// Keep API responses and exported diagnostics in sync, including saved presets.
extension AppSettings {
    func diagnosticPayload(defaultScreenshotsDirectory: URL) -> [String: Any] {
        [
            "hudEnabled": hudEnabled,
            "hudDurationSeconds": hudDurationSeconds,
            "hudFadeInSeconds": hudFadeInSeconds,
            "hudHoldSeconds": hudHoldSeconds,
            "hudScale": hudScale,
            "hudBackgroundOpacity": hudBackgroundOpacity,
            "hudPosition": hudPosition.rawValue,
            "hudShowsDesktopNumber": hudShowsDesktopNumber,
            "apiEnabled": apiEnabled,
            "globalHotkeyEnabled": globalHotkeyEnabled,
            "globalHotkeyShortcut": globalHotkeyShortcut,
            "notesOverlayHotkeyEnabled": notesOverlayHotkeyEnabled,
            "notesOverlayHotkeyShortcut": notesOverlayHotkeyShortcut,
            "notesOverlayItemOpacity": notesOverlayItemOpacity,
            "notesOverlayBackgroundOpacity": notesOverlayBackgroundOpacity,
            "notesOverlayHeightPixels": notesOverlayHeightPixels,
            "autoLaunchAssignedApps": autoLaunchAssignedApps,
            "onboardingCompleted": onboardingCompleted,
            "screenshotDirectoryPath": screenshotDirectoryPath,
            "effectiveScreenshotDirectory": screenshotDirectoryPath.isEmpty
                ? defaultScreenshotsDirectory.path
                : URL(fileURLWithPath: (screenshotDirectoryPath as NSString).expandingTildeInPath, isDirectory: true).path,
            "menuBarDisplayMode": menuBarDisplayMode.rawValue,
            "menuBarLabelPosition": menuBarLabelPosition.rawValue
        ]
    }
}
