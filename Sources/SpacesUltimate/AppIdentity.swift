import Foundation

enum AppIdentity {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    static var bundlePath: String {
        Bundle.main.bundlePath
    }

    static var executablePath: String {
        Bundle.main.executablePath ?? "unknown"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    static var processIdentifier: Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    static var permissionTargetSummary: String {
        "\(bundleIdentifier) at \(bundlePath)"
    }

    static func payload() -> [String: Any] {
        [
            "name": "SpacesUltimate",
            "bundleIdentifier": bundleIdentifier,
            "bundlePath": bundlePath,
            "executablePath": executablePath,
            "processIdentifier": processIdentifier,
            "version": version,
            "build": build,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString
        ]
    }
}
