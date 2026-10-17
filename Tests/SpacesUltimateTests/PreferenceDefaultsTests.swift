import AppKit
import XCTest
@testable import SpacesUltimate

@MainActor
final class PreferenceDefaultsTests: XCTestCase {
    func testOlderConfigUsesFactoryBaselineWithoutReplacingCurrentPreferences() throws {
        try withStore { store in
            var current = store.config.settings
            current.notesOverlayItemOpacity = 0.71
            store.updateSettings(current)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.configURL)) as? [String: Any])
            json.removeValue(forKey: "savedPreferenceDefaults")
            try JSONSerialization.data(withJSONObject: json).write(to: store.configURL)
            let reopened = SpaceStore()
            XCTAssertNil(reopened.config.savedPreferenceDefaults)
            XCTAssertEqual(reopened.preferenceDefaults, .factory)
            XCTAssertEqual(reopened.config.settings.notesOverlayItemOpacity, 0.71)
            XCTAssertEqual(reopened.preferenceDefaults.settings.notesOverlayItemOpacity, 0.34)
            XCTAssertFalse(reopened.preferenceDefaults.launchAtLogin)
        }
    }

    func testSavedDefaultSurvivesRelaunchAndCanBeReplacedDeliberately() throws {
        try withStore { store in
            var current = store.config.settings
            current.hudEnabled = false
            current.notesOverlayBackgroundOpacity = 0.21
            current.notesOverlayHotkeyEnabled = true
            store.updateSettings(current)
            store.saveCurrentPreferencesAsDefault(launchAtLogin: true)
            let first = try XCTUnwrap(store.config.savedPreferenceDefaults)
            XCTAssertNotNil(first.savedAt)
            XCTAssertTrue(first.launchAtLogin)
            XCTAssertEqual(first.settings, current)

            let reopened = SpaceStore()
            XCTAssertEqual(reopened.preferenceDefaults, first)
            current.notesOverlayBackgroundOpacity = 0.87
            reopened.updateSettings(current)
            XCTAssertEqual(reopened.preferenceDefaults, first)
            reopened.saveCurrentPreferencesAsDefault(launchAtLogin: false)
            XCTAssertEqual(SpaceStore().preferenceDefaults.settings.notesOverlayBackgroundOpacity, 0.87)
            XCTAssertFalse(SpaceStore().preferenceDefaults.launchAtLogin)
        }
    }

    func testRestoringDefaultAndFactoryPreservesDesktopDataAndSavedPreset() throws {
        try withStore { store in
            var desktop = store.space(orderIndex: 1)
            desktop.name = "Research"
            desktop.note = "Keep this note"
            desktop.shortcut = "Control+1"
            desktop.assignedApps = ["Safari"]
            store.update(desktop)
            var preferred = store.config.settings
            preferred.notesOverlayItemOpacity = 0.72
            preferred.notesOverlayBackgroundOpacity = 0.23
            preferred.hudFadeInSeconds = 0.5
            preferred.hudHoldSeconds = 2
            preferred.hudDurationSeconds = 4
            preferred.hudScale = 1.2
            preferred.hudBackgroundOpacity = 0.65
            preferred.hudPosition = .center
            preferred.hudShowsDesktopNumber = false
            preferred.onboardingCompleted = true
            store.updateSettings(preferred)
            store.saveCurrentPreferencesAsDefault(launchAtLogin: true)
            let snapshot = store.config

            var changed = preferred
            changed.notesOverlayItemOpacity = 0.19
            changed.hudEnabled = false
            store.updateSettings(changed)
            store.restorePreferences(from: store.preferenceDefaults)
            XCTAssertEqual(store.config.settings, preferred)
            store.restorePreferences(from: .factory)
            XCTAssertEqual(store.config.settings, PreferenceDefaults.factory.settingsToApply(preserving: preferred))
            XCTAssertTrue(store.config.settings.onboardingCompleted)
            XCTAssertEqual(store.config.spaces, snapshot.spaces)
            XCTAssertEqual(store.config.stableSpaceHistory, snapshot.stableSpaceHistory)
            XCTAssertEqual(store.config.lastKnownActiveOrderIndex, snapshot.lastKnownActiveOrderIndex)
            XCTAssertEqual(store.config.savedPreferenceDefaults, snapshot.savedPreferenceDefaults)
            XCTAssertFalse(store.listBackups().isEmpty)
            store.restorePreferences(from: store.preferenceDefaults)
            XCTAssertEqual(store.config.settings, preferred)
        }
    }

    func testDefaultComparisonIncludesLoginSettingButIgnoresOnboardingHistory() {
        var settings = AppSettings.defaults
        settings.onboardingCompleted = true
        XCTAssertTrue(PreferenceDefaults.factory.matches(settings, launchAtLogin: false))
        XCTAssertFalse(PreferenceDefaults.factory.matches(settings, launchAtLogin: true))
        settings.notesOverlayItemOpacity = 0.5
        XCTAssertFalse(PreferenceDefaults.factory.matches(settings, launchAtLogin: false))
    }

    func testPreferencesButtonsCaptureEditsAndIndividualResetUsesSavedDefault() throws {
        try withStore { store in
            _ = NSApplication.shared
            var preferred = store.config.settings
            preferred.notesOverlayItemOpacity = 0.61
            preferred.notesOverlayBackgroundOpacity = 0.31
            store.updateSettings(preferred)
            let controller = PreferencesWindowController(store: store, scanner: WindowScanner(),
                screenshotService: ScreenshotService(store: store), loginItemController: LoginItemController())
            let window = try XCTUnwrap(controller.window)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            controller.reload()
            let content = try XCTUnwrap(window.contentView)
            XCTAssertGreaterThanOrEqual(content.bounds.height, 600)
            XCTAssertEqual(controller.selectedCategory, .notes)
            controller.selectCategory(.defaults)
            let buttons = descendants(content).compactMap { $0 as? NSButton }
            let save = try XCTUnwrap(buttons.first { $0.title == "Save Current as Default" })
            let restore = try XCTUnwrap(buttons.first { $0.title == "Restore Default" })
            let factory = try XCTUnwrap(buttons.first { $0.title == "Factory Reset" })
            XCTAssertEqual(restore.action, NSSelectorFromString("restoreDefault"))
            XCTAssertEqual(factory.action, NSSelectorFromString("factoryReset"))
            XCTAssertFalse(window.initialFirstResponder is NSTextField)
            controller.selectCategory(.overview)
            let shortcut = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTextField }
                .first { $0.isEditable && $0.stringValue == AppSettings.defaults.globalHotkeyShortcut })
            shortcut.stringValue = "Control+Option+K"
            controller.selectCategory(.defaults)
            save.performClick(nil)
            XCTAssertEqual(store.preferenceDefaults.settings.globalHotkeyShortcut, "Control+Option+K")
            XCTAssertEqual(store.preferenceDefaults.settings.notesOverlayItemOpacity, 0.61)

            var changed = store.config.settings
            changed.notesOverlayItemOpacity = 0.2
            changed.notesOverlayBackgroundOpacity = 0.8
            store.updateSettings(changed)
            controller.reload()
            controller.selectCategory(.notes)
            let cardDefault = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }
                .first { $0.action == NSSelectorFromString("resetNotesOverlayOpacity") })
            cardDefault.performClick(nil)
            XCTAssertEqual(store.config.settings.notesOverlayItemOpacity, 0.61)
            XCTAssertEqual(store.config.settings.notesOverlayBackgroundOpacity, 0.8)
            XCTAssertTrue(restore.isEnabled)

            if let path = ProcessInfo.processInfo.environment["SPACESULTIMATE_PREFERENCES_PREVIEW_DIR"] {
                controller.selectCategory(.defaults)
                try render(content, to: URL(fileURLWithPath: path).appendingPathComponent("defaults-collapsed.png"))
                let show = try XCTUnwrap(buttons.first { $0.title == "Show default values" })
                show.performClick(nil)
                try render(content, to: URL(fileURLWithPath: path).appendingPathComponent("defaults-expanded.png"))
                for category in PreferencesCategory.allCases {
                    controller.selectCategory(category)
                    try render(content, to: URL(fileURLWithPath: path).appendingPathComponent("category-\(category.rawValue).png"))
                }
            }
        }
    }

    func testHUDPreviewUsesCurrentDesktopAndEditedControlsWhileAutomaticHUDIsDisabled() throws {
        try withStore { store in
            _ = NSApplication.shared
            store.setActiveOrderIndex(3)
            var space = store.space(orderIndex: 3)
            space.name = "Current Desktop Preview"
            store.update(space)
            var settings = store.config.settings
            settings.hudEnabled = false
            store.updateSettings(settings)
            let detector = SpaceDetector(store: store)
            let hud = HUDController(present: { _ in })
            defer { hud.hide() }
            var previewed: AppSettings?
            let controller = PreferencesWindowController(store: store, scanner: WindowScanner(),
                screenshotService: ScreenshotService(store: store), loginItemController: LoginItemController(),
                previewHUD: { settings in
                    previewed = settings
                    hud.show(store: store, detector: detector, settings: settings)
                })
            let window = try XCTUnwrap(controller.window)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            controller.reload()
            controller.selectCategory(.overview)
            let content = try XCTUnwrap(window.contentView)
            let fadeOut = try XCTUnwrap(descendants(content).compactMap { $0 as? NSSlider }
                .first { $0.accessibilityLabel() == "HUD fade out" })
            fadeOut.doubleValue = 4
            let test = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }
                .first { $0.title == "Test HUD for Current Desktop" })
            test.performClick(nil)
            XCTAssertEqual(previewed?.hudDurationSeconds, 4)
            XCTAssertEqual(previewed?.hudEnabled, false)
            XCTAssertFalse(store.config.settings.hudEnabled)
            XCTAssertEqual(store.config.lastKnownActiveOrderIndex, 3)
            XCTAssertFalse(window.firstResponder is NSTextField)
            XCTAssertFalse(hud.panels.isEmpty)
            for panel in hud.panels {
                let labels = descendants(try XCTUnwrap(panel.contentView)).compactMap { $0 as? NSTextField }.map(\.stringValue)
                XCTAssertTrue(labels.contains("Current Desktop Preview"))
                XCTAssertTrue(labels.contains("Desktop 3"))
                XCTAssertTrue(panel.ignoresMouseEvents)
                XCTAssertFalse(panel.canBecomeKey)
            }
            store.saveCurrentPreferencesAsDefault(launchAtLogin: false)
            fadeOut.doubleValue = 1
            test.performClick(nil)
            let reset = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }
                .first { $0.action == NSSelectorFromString("resetHUDSlider:") && $0.tag == 2 })
            reset.performClick(nil)
            XCTAssertEqual(store.config.settings.hudDurationSeconds, 4)
        }
    }

    private func render(_ view: NSView, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        view.appearance = NSAppearance(named: .aqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func withStore(_ body: (SpaceStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PreferenceDefaultsTests-\(UUID().uuidString)")
        let previous = ProcessInfo.processInfo.environment["SPACESULTIMATE_CONFIG_DIR"]
        setenv("SPACESULTIMATE_CONFIG_DIR", directory.path, 1)
        defer {
            if let previous { setenv("SPACESULTIMATE_CONFIG_DIR", previous, 1) }
            else { unsetenv("SPACESULTIMATE_CONFIG_DIR") }
            try? FileManager.default.removeItem(at: directory)
        }
        try body(SpaceStore())
    }
}
