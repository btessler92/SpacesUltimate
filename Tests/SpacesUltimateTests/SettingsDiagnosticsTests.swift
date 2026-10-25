import XCTest
@testable import SpacesUltimate

final class SettingsDiagnosticsTests: XCTestCase {
    func testDiagnosticsIncludesAllPersistedSettingsIncludingCustomHUDValues() throws {
        var settings = AppSettings.defaults
        settings.hudFadeInSeconds = 0.4
        settings.hudHoldSeconds = 1.2
        settings.hudDurationSeconds = 2.3
        settings.hudScale = 1.4
        settings.hudBackgroundOpacity = 0.7
        settings.hudPosition = .left
        settings.hudShowsDesktopNumber = false

        var payload = settings.diagnosticPayload(defaultScreenshotsDirectory: URL(fileURLWithPath: "/test/screenshots"))
        payload.removeValue(forKey: "effectiveScreenshotDirectory")
        let persisted = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? NSDictionary)
        XCTAssertEqual(payload as NSDictionary, persisted)
    }

    func testDiagnosticsResolvesDirectoryForEachPresetInsteadOfUsingCurrentSettings() {
        let defaultDirectory = URL(fileURLWithPath: "/test/default-screenshots")
        let factory = AppSettings.defaults.diagnosticPayload(defaultScreenshotsDirectory: defaultDirectory)
        XCTAssertEqual(factory["effectiveScreenshotDirectory"] as? String, defaultDirectory.path)

        var preset = AppSettings.defaults
        preset.screenshotDirectoryPath = "~/Pictures/Space previews"
        let payload = preset.diagnosticPayload(defaultScreenshotsDirectory: defaultDirectory)
        XCTAssertEqual(payload["screenshotDirectoryPath"] as? String, "~/Pictures/Space previews")
        XCTAssertEqual(payload["effectiveScreenshotDirectory"] as? String,
                       ("~/Pictures/Space previews" as NSString).expandingTildeInPath)
    }
}
