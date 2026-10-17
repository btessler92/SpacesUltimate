import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ScreenshotService {
    private let store: SpaceStore

    init(store: SpaceStore) {
        self.store = store
    }

    var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCaptureIfNeeded() -> Bool {
        guard !isScreenCaptureTrusted else {
            AppLog.shared.info("Screen Recording already trusted for \(AppIdentity.permissionTargetSummary)")
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    func captureScreens() throws -> [URL] {
        guard isScreenCaptureTrusted else {
            throw ScreenshotError.permissionRequired
        }

        let directory = screenshotsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = Self.timestamp.string(from: Date())
        return try NSScreen.screens.enumerated().compactMap { index, screen in
            guard let displayID = Self.displayID(for: screen),
                  let image = CGDisplayCreateImage(displayID) else {
                return nil
            }
            let url = directory.appendingPathComponent("spacesultimate-\(stamp)-display-\(index + 1).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw ScreenshotError.destinationFailed
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw ScreenshotError.writeFailed
            }
            return url
        }
    }

    var screenshotsDirectory: URL {
        let configuredPath = store.config.settings.screenshotDirectoryPath
        if !configuredPath.isEmpty {
            return URL(fileURLWithPath: (configuredPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return defaultScreenshotsDirectory
    }

    var defaultScreenshotsDirectory: URL {
        store.configURL
            .deletingLastPathComponent()
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    enum ScreenshotError: LocalizedError {
        case permissionRequired
        case destinationFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .permissionRequired:
                "Screen Recording permission is not granted for \(AppIdentity.permissionTargetSummary)."
            case .destinationFailed:
                "Could not create PNG destination."
            case .writeFailed:
                "Could not write PNG screenshot."
            }
        }
    }
}
