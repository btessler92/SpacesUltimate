import AppKit
import XCTest
@testable import SpacesUltimate

@MainActor
final class HUDTests: XCTestCase {
    func testFadeInHoldAndSlowFadeOutAreSeparate() {
        var settings = AppSettings.defaults
        settings.hudFadeInSeconds = 1
        settings.hudHoldSeconds = 2
        settings.hudDurationSeconds = 4
        let timeline = HUDTimeline(settings: settings)
        XCTAssertEqual(timeline.duration, 7)
        for (time, alpha) in [(-1.0, 0.0), (0, 0), (0.5, 0.5), (1, 1), (2, 1), (3, 1), (5, 0.5), (7, 0), (9, 0)] {
            XCTAssertEqual(timeline.opacity(at: time), alpha, accuracy: 0.001)
        }
        let legacy = HUDTimeline(settings: .defaults)
        XCTAssertEqual(legacy.opacity(at: 0), 1)
        XCTAssertEqual(legacy.opacity(at: 0.5), 0.5)
        XCTAssertEqual(legacy.opacity(at: 1), 0)
    }

    func testHUDPositionsAndScaleStayOnEachDisplay() {
        for screen in [NSRect(x: -1728, y: -200, width: 1728, height: 1000),
                       NSRect(x: 2000, y: 500, width: 320, height: 180)] {
            for position in HUDPosition.allCases {
                for scale in [0.7, 1.0, 1.5] {
                    var settings = AppSettings.defaults
                    settings.hudPosition = position
                    settings.hudScale = scale
                    let frame = HUDLayout.frame(visibleFrame: screen, settings: settings)
                    XCTAssertTrue(screen.contains(frame))
                    if position == .center { XCTAssertEqual(frame.midX, screen.midX); XCTAssertEqual(frame.midY, screen.midY) }
                    let margin = min(28, min(screen.width, screen.height) / 10)
                    if position == .right { XCTAssertEqual(frame.maxX, screen.maxX - margin, accuracy: 0.001) }
                    if position == .left { XCTAssertEqual(frame.minX, screen.minX + margin, accuracy: 0.001) }
                    if position == .top { XCTAssertEqual(frame.maxY, screen.maxY - margin, accuracy: 0.001) }
                    if position == .bottom { XCTAssertEqual(frame.minY, screen.minY + margin, accuracy: 0.001) }
                }
            }
        }
    }

    func testReplacingHUDCancelsOldAnimationWithoutClosingNewPanels() throws {
        _ = NSApplication.shared
        var now = 0.0
        let controller = HUDController(clock: { now }, present: { _ in })
        defer { controller.hide() }
        let spaces = SpaceConfig.defaults(spaceCount: 2).spaces
        var settings = AppSettings.defaults
        settings.hudDurationSeconds = 0.2
        controller.show(space: spaces[0], desktopNumber: 1, settings: settings)
        let oldGeneration = controller.generation
        let oldPanels = controller.panels
        now = 0.1
        settings.hudDurationSeconds = 2
        controller.show(space: spaces[1], desktopNumber: 2, settings: settings)
        let newPanels = controller.panels
        XCTAssertFalse(newPanels.isEmpty)
        XCTAssertFalse(newPanels.contains { panel in oldPanels.contains { $0 === panel } })
        now = 0.5
        controller.advanceAnimation(generation: oldGeneration)
        XCTAssertEqual(controller.panels, newPanels)
        XCTAssertEqual(try XCTUnwrap(controller.panels.first).alphaValue, 1)
        controller.advanceAnimation(generation: controller.generation)
        XCTAssertEqual(try XCTUnwrap(controller.panels.first).alphaValue, 0.896, accuracy: 0.001)
        now = 2.2
        controller.advanceAnimation(generation: controller.generation)
        XCTAssertTrue(controller.panels.isEmpty)
    }

    func testHUDTextFitsAndAppearanceOptionsRender() throws {
        _ = NSApplication.shared
        for scale in [0.7, 1.0, 1.5] {
            for showsNumber in [true, false] {
                for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    var settings = AppSettings.defaults
                    settings.hudScale = scale
                    settings.hudShowsDesktopNumber = showsNumber
                    settings.hudBackgroundOpacity = 0.65
                    var space = SpaceConfig.defaults().spaces[0]
                    space.name = "Research and writing with a longer Desktop name"
                    space.icon = "🔬"
                    let size = NSSize(width: 360 * scale, height: 160 * scale)
                    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.isReleasedWhenClosed = false
                    panel.appearance = NSAppearance(named: appearance)
                    let view = HUDView(space: space, desktopNumber: 12, settings: settings, size: size)
                    panel.contentView = view
                    view.layoutSubtreeIfNeeded()
                    let fields = descendants(view).compactMap { $0 as? NSTextField }
                    XCTAssertEqual(fields.count, showsNumber ? 2 : 1)
                    XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? 0, 0.65, accuracy: 0.001)
                    for field in fields {
                        XCTAssertTrue(view.bounds.contains(field.convert(field.bounds, to: view)))
                    }
                    if let directory = ProcessInfo.processInfo.environment["SPACESULTIMATE_HUD_PREVIEW_DIR"] {
                        let url = URL(fileURLWithPath: directory).appendingPathComponent("hud-\(Int(scale * 100))-\(showsNumber ? "number" : "name")-\(theme).png")
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
                    }
                    panel.close()
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
