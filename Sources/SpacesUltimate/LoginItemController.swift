import Foundation
import ServiceManagement

@MainActor
final class LoginItemController {
    struct State: Equatable {
        var supported: Bool
        var enabled: Bool
        var status: String
        var canRegister: Bool
        var requiresUserApproval: Bool
        var recoverySuggestion: String
        var bundlePath: String
    }

    var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "enabled"
        case .notRegistered:
            return "not registered"
        case .notFound:
            return "not found"
        case .requiresApproval:
            return "requires approval"
        @unknown default:
            return "unknown"
        }
    }

    var state: State {
        let status = SMAppService.mainApp.status
        return State(
            supported: isSupported,
            enabled: status == .enabled,
            status: statusDescription,
            canRegister: status == .notRegistered || status == .notFound,
            requiresUserApproval: status == .requiresApproval,
            recoverySuggestion: recoverySuggestion(for: status),
            bundlePath: Bundle.main.bundlePath
        )
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        AppLog.shared.info("Launch at login \(enabled ? "enabled" : "disabled"); status=\(statusDescription)")
    }

    private func recoverySuggestion(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "Launch at login is enabled for this app bundle."
        case .notRegistered:
            return "Enable Launch at Login from Preferences after installing SpacesUltimate in a stable location such as ~/Applications."
        case .notFound:
            return "Reinstall SpacesUltimate in a stable location, quit any old copy, relaunch this bundle, then enable Launch at Login again."
        case .requiresApproval:
            return "Approve SpacesUltimate in System Settings > General > Login Items, then relaunch or refresh Preferences."
        @unknown default:
            return "Open System Settings > General > Login Items and verify the SpacesUltimate entry."
        }
    }
}
