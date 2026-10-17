import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class SpacePreviewService {
    struct PreviewInfo: Equatable {
        var url: URL
        var modifiedAt: Date?
    }

    private let store: SpaceStore

    init(store: SpaceStore) {
        self.store = store
    }

    var previewsDirectory: URL {
        store.configURL
            .deletingLastPathComponent()
            .appendingPathComponent("SpacePreviews", isDirectory: true)
    }

    var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func capturePreview(for space: SpaceMetadata) {
        guard isScreenCaptureTrusted else { return }
        do {
            try FileManager.default.createDirectory(at: previewsDirectory, withIntermediateDirectories: true)
            guard let displayID = Self.displayID(for: NSScreen.main ?? NSScreen.screens.first),
                  let image = CGDisplayCreateImage(displayID) else {
                AppLog.shared.warning("Could not capture Space preview for Desktop \(space.orderIndex).")
                return
            }
            try writePNG(image, to: previewURL(for: space))
            AppLog.shared.info("Captured preview for Desktop \(space.orderIndex).")
        } catch {
            AppLog.shared.warning("Space preview capture failed: \(error.localizedDescription)")
        }
    }

    func previewURL(for space: SpaceMetadata) -> URL {
        previewsDirectory.appendingPathComponent("\(previewIdentifier(for: space)).png")
    }

    func existingPreviewURL(for space: SpaceMetadata) -> URL? {
        existingPreviewInfo(for: space)?.url
    }

    func existingPreviewInfo(for space: SpaceMetadata) -> PreviewInfo? {
        let url = previewURL(for: space)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return PreviewInfo(url: url, modifiedAt: modifiedAt)
    }

    func previewPayload() -> [[String: Any]] {
        store.spaces.map { space in
            let info = existingPreviewInfo(for: space)
            return [
                "space": space.orderIndex,
                "name": space.displayName,
                "file": info?.url.path ?? NSNull(),
                "modifiedAt": info?.modifiedAt.map(Self.isoTimestamp.string(from:)) ?? NSNull()
            ]
        }
    }

    private func previewIdentifier(for space: SpaceMetadata) -> String {
        let raw = space.stableID ?? "order-\(space.orderIndex)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce(into: "") { $0.append($1) }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PreviewError.destinationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PreviewError.writeFailed
        }
    }

    private static func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static let isoTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    enum PreviewError: LocalizedError {
        case destinationFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .destinationFailed:
                "Could not create preview PNG destination."
            case .writeFailed:
                "Could not write preview PNG."
            }
        }
    }
}
