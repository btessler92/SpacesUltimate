import XCTest
@testable import SpacesUltimate

final class AppSettingsTests: XCTestCase {
    func testHUDOptionsMigratePersistAndNormalize() throws {
        let legacy = Data(#"{"hudEnabled":false,"hudDurationSeconds":2.4}"#.utf8)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertFalse(migrated.hudEnabled)
        XCTAssertEqual(migrated.hudDurationSeconds, 2.4)
        XCTAssertEqual(migrated.hudFadeInSeconds, 0)
        XCTAssertEqual(migrated.hudHoldSeconds, 0)
        XCTAssertEqual(migrated.hudScale, 1)
        XCTAssertEqual(migrated.hudBackgroundOpacity, 0.94)
        XCTAssertEqual(migrated.hudPosition, .right)
        XCTAssertTrue(migrated.hudShowsDesktopNumber)
        var custom = migrated
        custom.hudFadeInSeconds = 0.4
        custom.hudHoldSeconds = 2
        custom.hudDurationSeconds = 4
        custom.hudScale = 1.3
        custom.hudBackgroundOpacity = 0.5
        custom.hudPosition = .bottom
        custom.hudShowsDesktopNumber = false
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom)), custom)
        custom.hudFadeInSeconds = -1
        custom.hudHoldSeconds = 99
        custom.hudDurationSeconds = 99
        custom.hudScale = 0
        custom.hudBackgroundOpacity = .nan
        XCTAssertEqual(custom.normalized.hudFadeInSeconds, 0)
        XCTAssertEqual(custom.normalized.hudHoldSeconds, 10)
        XCTAssertEqual(custom.normalized.hudDurationSeconds, 10)
        XCTAssertEqual(custom.normalized.hudScale, 0.7)
        XCTAssertEqual(custom.normalized.hudBackgroundOpacity, 0.94)
        let invalidPosition = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"hudPosition":"unknown"}"#.utf8))
        XCTAssertEqual(invalidPosition.hudPosition, .right)
    }

    func testMissingMenuBarLabelPositionDefaultsToRightOfCenter() throws {
        let json = """
        {
          "hudEnabled": true,
          "hudDurationSeconds": 1.0,
          "apiEnabled": true,
          "globalHotkeyEnabled": false,
          "onboardingCompleted": true,
          "screenshotDirectoryPath": "",
          "menuBarDisplayMode": "name",
          "globalHotkeyShortcut": "Command+Option+Space",
          "autoLaunchAssignedApps": false
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.menuBarLabelPosition, .rightOfCenter)
        XCTAssertFalse(settings.notesOverlayHotkeyEnabled)
        XCTAssertEqual(settings.notesOverlayHotkeyShortcut, "Command+Option+N")
        XCTAssertEqual(settings.notesOverlayItemOpacity, AppSettings.defaults.notesOverlayItemOpacity)
        XCTAssertEqual(settings.notesOverlayBackgroundOpacity, 0.58)
        XCTAssertEqual(settings.notesOverlayHeightPixels, AppSettings.defaults.notesOverlayHeightPixels)
    }

    func testInvalidMenuBarLabelPositionDefaultsToRightOfCenter() throws {
        let json = """
        {
          "hudEnabled": true,
          "hudDurationSeconds": 1.0,
          "apiEnabled": true,
          "globalHotkeyEnabled": false,
          "onboardingCompleted": true,
          "screenshotDirectoryPath": "",
          "menuBarDisplayMode": "name",
          "menuBarLabelPosition": "somewhereImpossible",
          "globalHotkeyShortcut": "Command+Option+Space",
          "autoLaunchAssignedApps": false
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.menuBarLabelPosition, .rightOfCenter)
    }

    func testInvalidNotesOverlayHotkeyNormalizesToDefault() {
        let settings = AppSettings(
            hudEnabled: true,
            hudDurationSeconds: 1.0,
            apiEnabled: true,
            globalHotkeyEnabled: false,
            onboardingCompleted: true,
            notesOverlayHotkeyEnabled: true,
            notesOverlayHotkeyShortcut: "Control+Banana"
        ).normalized

        XCTAssertTrue(settings.notesOverlayHotkeyEnabled)
        XCTAssertEqual(settings.notesOverlayHotkeyShortcut, "Command+Option+N")
    }

    func testNotesOverlayItemOpacityNormalizesToSliderRange() {
        let tooLow = AppSettings(
            hudEnabled: true,
            hudDurationSeconds: 1.0,
            apiEnabled: true,
            globalHotkeyEnabled: false,
            onboardingCompleted: true,
            notesOverlayItemOpacity: -1
        ).normalized
        let tooHigh = AppSettings(
            hudEnabled: true,
            hudDurationSeconds: 1.0,
            apiEnabled: true,
            globalHotkeyEnabled: false,
            onboardingCompleted: true,
            notesOverlayItemOpacity: 2
        ).normalized

        XCTAssertEqual(tooLow.notesOverlayItemOpacity, 0.12)
        XCTAssertEqual(tooHigh.notesOverlayItemOpacity, 0.90)
    }

    func testNotesOverlayHeightNormalizesToSliderRange() {
        let tooShort = AppSettings(
            hudEnabled: true,
            hudDurationSeconds: 1.0,
            apiEnabled: true,
            globalHotkeyEnabled: false,
            onboardingCompleted: true,
            notesOverlayHeightPixels: 10
        ).normalized
        let tooTall = AppSettings(
            hudEnabled: true,
            hudDurationSeconds: 1.0,
            apiEnabled: true,
            globalHotkeyEnabled: false,
            onboardingCompleted: true,
            notesOverlayHeightPixels: 500
        ).normalized

        XCTAssertEqual(tooShort.notesOverlayHeightPixels, AppSettings.minimumNotesOverlayHeightPixels)
        XCTAssertEqual(tooTall.notesOverlayHeightPixels, AppSettings.maximumNotesOverlayHeightPixels)
    }

    func testBackgroundOpacityClampsIndependentlyOfCardOpacity() {
        var settings = AppSettings.defaults
        settings.notesOverlayItemOpacity = 0.73
        settings.notesOverlayBackgroundOpacity = -1
        XCTAssertEqual(settings.normalized.notesOverlayBackgroundOpacity, 0)
        XCTAssertEqual(settings.normalized.notesOverlayItemOpacity, 0.73)
        settings.notesOverlayBackgroundOpacity = 2
        XCTAssertEqual(settings.normalized.notesOverlayBackgroundOpacity, 1)
    }

    func testIndependentOpacitiesPersistAndOlderConfigsKeepTheirCardOpacity() throws {
        var settings = AppSettings.defaults
        settings.notesOverlayItemOpacity = 0.73
        settings.notesOverlayBackgroundOpacity = 0.19
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(restored.notesOverlayItemOpacity, 0.73)
        XCTAssertEqual(restored.notesOverlayBackgroundOpacity, 0.19)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "notesOverlayBackgroundOpacity")
        let migrated = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.notesOverlayItemOpacity, 0.73)
        XCTAssertEqual(migrated.notesOverlayBackgroundOpacity, 0.58)
    }
}
