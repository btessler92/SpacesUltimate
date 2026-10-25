import Foundation

/// A validated live ordering. Only ordinary Desktops consume Desktop numbers.
/// Fullscreen cards use negative, transient keys; these are never saved as Desktops.
@MainActor
struct LiveSpaceInventory {
    let displays: [LiveSpaceReader.Display]
    let desktops: [DetectedSpace]
    let fullscreenCards: [SpaceMetadata]

    init?(displays: [LiveSpaceReader.Display]) {
        guard !displays.isEmpty else { return nil }
        var displayIDs = Set<String>()
        var spaceIDs = Set<String>()
        var desktops: [DetectedSpace] = []
        var fullscreen: [SpaceMetadata] = []
        for display in displays {
            guard displayIDs.insert(display.identifier.lowercased()).inserted,
                  let spaces = display.spaces, !spaces.isEmpty,
                  spaces.contains(where: { $0.stableID == display.currentStableID }) else { return nil }
            for space in spaces {
                guard spaceIDs.insert(space.stableID).inserted else { return nil }
                switch space.type {
                case 0:
                    desktops.append(DetectedSpace(stableID: space.stableID, orderIndex: desktops.count + 1))
                case 4:
                    fullscreen.append(SpaceMetadata(id: space.stableID, stableID: space.stableID,
                        orderIndex: -(fullscreen.count + 1), name: space.appName ?? "Fullscreen app",
                        colorHex: "#778899", icon: "", shortcut: "", assignedApps: []))
                default: return nil
                }
            }
        }
        guard !desktops.isEmpty else { return nil }
        self.displays = displays
        self.desktops = desktops
        fullscreenCards = fullscreen
    }

    func fullscreenCard(stableID: String?) -> SpaceMetadata? {
        fullscreenCards.first { $0.stableID == stableID }
    }

    func cards(for display: LiveSpaceReader.Display, savedSpaces: [SpaceMetadata]) -> [SpaceMetadata] {
        (display.spaces ?? []).compactMap { managed in
            if let fullscreen = fullscreenCard(stableID: managed.stableID) { return fullscreen }
            return savedSpaces.first { $0.stableID == managed.stableID }
        }
    }

    /// Keyboard arrows visit fullscreen Spaces too, unlike Desktop numbers.
    func relativeOffset(to stableID: String) -> Int? {
        for display in displays {
            guard let spaces = display.spaces,
                  let target = spaces.firstIndex(where: { $0.stableID == stableID }),
                  let current = spaces.firstIndex(where: { $0.stableID == display.currentStableID }) else { continue }
            return target - current
        }
        return nil
    }
}
