import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class WindowScanner {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityTrusted else {
            AppLog.shared.info("Accessibility already trusted for \(AppIdentity.permissionTargetSummary)")
            return
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func scanVisibleWindows() -> [ScannedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { info in
            guard let appName = info[kCGWindowOwnerName as String] as? String,
                  !["Dock", "Window Server", "SystemUIServer"].contains(appName),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            let title = info[kCGWindowName as String] as? String ?? ""
            return ScannedWindow(
                appName: appName,
                title: title,
                screenName: Self.screenName(for: bounds),
                bounds: bounds
            )
        }
    }

    private static func screenName(for bounds: CGRect) -> String {
        NSScreen.screens.first(where: { $0.frame.intersects(bounds) })?.localizedName ?? "Unknown Display"
    }
}
