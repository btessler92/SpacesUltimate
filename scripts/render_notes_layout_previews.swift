import AppKit

/// Render the production AppKit views without activating apps or capturing unrelated windows.
@main
struct NotesLayoutPreviews {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fatalError("Usage: render-notes-previews OUTPUT_DIRECTORY [CONFIG_JSON]")
        }
        let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let config: SpaceConfig
        if arguments.count > 2 {
            config = try JSONDecoder().decode(SpaceConfig.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
        } else {
            var defaults = SpaceConfig.defaults(spaceCount: 16)
            let names = ["Extra", "Personal", "Email", "RPpaper", "Fusion MCP", "3D Database", "SunWiki", "Obsidian",
                         "Desktop 9", "MouseTracker", "Desktop 11", "SURGREVIEW", "Desktop 13", "SurgDocs", "Desktop 15", "Windows"]
            for index in defaults.spaces.indices { defaults.spaces[index].name = names[index] }
            config = defaults
        }
        _ = NSApplication.shared
        var spacesWithNotes = config.spaces
        for index in spacesWithNotes.indices { spacesWithNotes[index].note = "Reference notes for this Desktop" }
        var withFullscreen = config.spaces
        withFullscreen.insert(SpaceMetadata(id: "fullscreen-preview", stableID: "fullscreen-preview",
            orderIndex: -1, name: "Windows App", colorHex: "#778899", icon: "", shortcut: "", assignedApps: []),
            at: min(4, withFullscreen.count))
        var longNames = withFullscreen
        for index in longNames.indices where !longNames[index].isFullscreen {
            longNames[index].name = "Longer Desktop project title"
        }
        var secondary = SpaceConfig.defaults(spaceCount: 17).spaces[16]
        secondary.name = "Desktop 17"
        let height = config.settings.notesOverlayHeightPixels
        let scenarios: [(String, CGFloat, [SpaceMetadata], Double)] = [
            ("laptop", 1728, config.spaces, height),
            ("wide-display", 2560, config.spaces, height),
            ("wide-fullscreen", 2560, withFullscreen, height),
            ("ultrawide-fullscreen", 3840, withFullscreen, height),
            ("secondary-single-desktop", 1080, [secondary], height),
            ("wide-two-rows", 2560, longNames, height),
            ("compact-display", 1280, config.spaces, height),
            ("few-desktops", 1728, Array(config.spaces.prefix(4)), height),
            ("minimum-height-notes", 1728, spacesWithNotes, AppSettings.minimumNotesOverlayHeightPixels),
            ("taller-notes", 1728, spacesWithNotes, 82)
        ]
        for (name, screenWidth, spaces, baseHeight) in scenarios {
            for (theme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let width = NotesOverlayLayout.panelWidth(visibleWidth: screenWidth, spaceCount: spaces.count)
                let layout = NotesOverlayLayout(spaces: spaces, availableWidth: width)
                let frame = layout.panelFrame(visibleFrame: NSRect(x: 0, y: 0, width: screenWidth, height: 1000),
                                              width: width, baseHeight: baseHeight)
                let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                let previewAppearance = NSAppearance(named: appearance)!
                panel.appearance = previewAppearance
                // Resolve layer colors and translucent text in the preview's theme,
                // even when it differs from the current desktop appearance.
                var view: LabelOverlayView!
                previewAppearance.performAsCurrentDrawingAppearance {
                    view = LabelOverlayView(spaces: spaces, activeIndex: min(8, spaces.count),
                        itemOpacity: config.settings.notesOverlayItemOpacity,
                        backgroundOpacity: config.settings.notesOverlayBackgroundOpacity,
                        screenFrame: NSRect(origin: .zero, size: frame.size), presentationLayout: layout,
                        beginEditing: {}, rename: { _ in }, close: {})
                }
                panel.contentView = view
                view.layoutSubtreeIfNeeded()
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let destination = output.appendingPathComponent("\(name)-\(theme).png")
                try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
                print("\(name) \(theme): \(layout.rowCount) row(s), \(Int(frame.width))×\(Int(frame.height)), card width \(Int(layout.cardWidth)), minimum single-row name visible \(Int(layout.minimumSingleRowNameFraction * 100))%: \(destination.path)")
                panel.close()
            }
        }
    }
}
