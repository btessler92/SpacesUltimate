import AppKit
import Foundation

struct SpaceMetadata: Codable, Identifiable, Equatable {
    var id: String
    var stableID: String?
    var orderIndex: Int
    var name: String
    var colorHex: String
    var icon: String
    var note: String
    var shortcut: String
    var assignedApps: [String]

    // Only transient fullscreen overlay/menu cards have a negative key.
    var isFullscreen: Bool { orderIndex < 0 }

    var desktopLabel: String {
        isFullscreen ? "Fullscreen app" : "Desktop \(orderIndex)"
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? desktopLabel : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case stableID
        case orderIndex
        case name
        case colorHex
        case icon
        case note
        case shortcut
        case assignedApps
    }

    init(
        id: String,
        stableID: String?,
        orderIndex: Int,
        name: String,
        colorHex: String,
        icon: String,
        note: String = "",
        shortcut: String,
        assignedApps: [String]
    ) {
        self.id = id
        self.stableID = stableID
        self.orderIndex = orderIndex
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.note = note
        self.shortcut = shortcut
        self.assignedApps = assignedApps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        stableID = try container.decodeIfPresent(String.self, forKey: .stableID)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
        assignedApps = try container.decodeIfPresent([String].self, forKey: .assignedApps) ?? []
    }
}

struct SpaceConfig: Codable, Equatable {
    var spaces: [SpaceMetadata]
    var stableSpaceHistory: [String: SpaceMetadata]
    var lastKnownActiveOrderIndex: Int
    // Legacy config fields retained for lossless import/export. Runtime shortcuts
    // now live in AppSettings; no experimental switching mode is implemented.
    var overviewShortcut: String
    var riskyMethodsEnabled: Bool
    var settings: AppSettings
    var savedPreferenceDefaults: PreferenceDefaults?

    static func defaults(spaceCount: Int = 4) -> SpaceConfig {
        let count = max(1, spaceCount)
        return SpaceConfig(
            spaces: (1...count).map { index in
                SpaceMetadata(
                    id: "order-\(index)",
                    stableID: nil,
                    orderIndex: index,
                    name: "Desktop \(index)",
                    colorHex: spectrumColorHex(orderIndex: index, totalCount: count),
                    icon: "",
                    note: "",
                    shortcut: "",
                    assignedApps: []
                )
            },
            stableSpaceHistory: [:],
            lastKnownActiveOrderIndex: 1,
            overviewShortcut: "",
            riskyMethodsEnabled: false,
            settings: .defaults
        )
    }

    static func spectrumColorHex(orderIndex: Int, totalCount: Int) -> String {
        let count = max(1, totalCount)
        let position = count == 1 ? 0 : Double(max(0, orderIndex - 1)) / Double(count - 1)
        let hue = min(0.62, max(0, position * 0.62))
        return NSColor(calibratedHue: CGFloat(hue), saturation: 0.72, brightness: 0.92, alpha: 1).hexString
    }

    enum CodingKeys: String, CodingKey {
        case spaces
        case stableSpaceHistory
        case lastKnownActiveOrderIndex
        case overviewShortcut
        case riskyMethodsEnabled
        case settings
        case savedPreferenceDefaults
    }

    init(
        spaces: [SpaceMetadata],
        stableSpaceHistory: [String: SpaceMetadata] = [:],
        lastKnownActiveOrderIndex: Int,
        overviewShortcut: String,
        riskyMethodsEnabled: Bool,
        settings: AppSettings,
        savedPreferenceDefaults: PreferenceDefaults? = nil
    ) {
        self.spaces = spaces
        self.stableSpaceHistory = stableSpaceHistory
        self.lastKnownActiveOrderIndex = lastKnownActiveOrderIndex
        self.overviewShortcut = overviewShortcut
        self.riskyMethodsEnabled = riskyMethodsEnabled
        self.settings = settings
        self.savedPreferenceDefaults = savedPreferenceDefaults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try container.decode([SpaceMetadata].self, forKey: .spaces)
        stableSpaceHistory = try container.decodeIfPresent([String: SpaceMetadata].self, forKey: .stableSpaceHistory) ?? [:]
        lastKnownActiveOrderIndex = try container.decodeIfPresent(Int.self, forKey: .lastKnownActiveOrderIndex) ?? 1
        overviewShortcut = try container.decodeIfPresent(String.self, forKey: .overviewShortcut) ?? ""
        riskyMethodsEnabled = try container.decodeIfPresent(Bool.self, forKey: .riskyMethodsEnabled) ?? false
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .defaults
        savedPreferenceDefaults = try container.decodeIfPresent(PreferenceDefaults.self, forKey: .savedPreferenceDefaults)
    }
}

struct PreferenceDefaults: Codable, Equatable {
    var settings: AppSettings
    var launchAtLogin: Bool
    var savedAt: Date?

    static let factory = PreferenceDefaults(settings: .defaults, launchAtLogin: false, savedAt: nil)

    func settingsToApply(preserving current: AppSettings) -> AppSettings {
        var result = settings.normalized
        // Onboarding completion is app history, not a user preference.
        result.onboardingCompleted = current.onboardingCompleted
        return result
    }

    func matches(_ current: AppSettings, launchAtLogin: Bool) -> Bool {
        settingsToApply(preserving: current) == current.normalized && self.launchAtLogin == launchAtLogin
    }

    var displayedValues: [(name: String, value: String)] {
        let values = settings.normalized
        func enabled(_ value: Bool) -> String { value ? "On" : "Off" }
        return [
            ("Space-change HUD", enabled(values.hudEnabled)),
            ("HUD fade in", String(format: "%.1f seconds", values.hudFadeInSeconds)),
            ("HUD hold", String(format: "%.1f seconds", values.hudHoldSeconds)),
            ("HUD fade out", String(format: "%.1f seconds", values.hudDurationSeconds)),
            ("HUD size", String(format: "%.0f%%", values.hudScale * 100)),
            ("HUD background", String(format: "%.0f%%", values.hudBackgroundOpacity * 100)),
            ("HUD position", values.hudPosition.label),
            ("HUD Desktop number", enabled(values.hudShowsDesktopNumber)),
            ("Control API", enabled(values.apiEnabled)),
            ("Overview hotkey enabled", enabled(values.globalHotkeyEnabled)),
            ("Overview hotkey", values.globalHotkeyShortcut),
            ("Notes hotkey enabled", enabled(values.notesOverlayHotkeyEnabled)),
            ("Notes hotkey", values.notesOverlayHotkeyShortcut),
            ("Card opacity", String(format: "%.0f%%", values.notesOverlayItemOpacity * 100)),
            ("Background opacity", String(format: "%.0f%%", values.notesOverlayBackgroundOpacity * 100)),
            ("Overlay row height", String(format: "%.0f px", values.notesOverlayHeightPixels)),
            ("Status item contents", values.menuBarDisplayMode.label),
            ("Menu bar label", values.menuBarLabelPosition == .hidden ? "Hidden" : "Shown"),
            ("Auto-launch assigned apps", enabled(values.autoLaunchAssignedApps)),
            ("Launch at login", enabled(launchAtLogin)),
            ("Screenshot directory", values.screenshotDirectoryPath.isEmpty ? "App default directory" : values.screenshotDirectoryPath)
        ]
    }
}

struct AppSettings: Codable, Equatable {
    var hudEnabled: Bool
    // Retain the existing storage/API key: this has always controlled fade-out time.
    var hudDurationSeconds: Double
    var hudFadeInSeconds: Double
    var hudHoldSeconds: Double
    var hudScale: Double
    var hudBackgroundOpacity: Double
    var hudPosition: HUDPosition
    var hudShowsDesktopNumber: Bool
    var apiEnabled: Bool
    var globalHotkeyEnabled: Bool
    var onboardingCompleted: Bool
    var screenshotDirectoryPath: String
    var menuBarDisplayMode: MenuBarDisplayMode
    var menuBarLabelPosition: MenuBarLabelPosition
    var globalHotkeyShortcut: String
    var notesOverlayHotkeyEnabled: Bool
    var notesOverlayHotkeyShortcut: String
    var notesOverlayItemOpacity: Double
    var notesOverlayBackgroundOpacity: Double
    var notesOverlayHeightPixels: Double
    var autoLaunchAssignedApps: Bool

    static let minimumNotesOverlayHeightPixels = 56.0
    static let maximumNotesOverlayHeightPixels = 180.0

    static let defaults = AppSettings(
        hudEnabled: true,
        hudDurationSeconds: 1.0,
        apiEnabled: false,
        globalHotkeyEnabled: false,
        onboardingCompleted: false,
        screenshotDirectoryPath: "",
        menuBarDisplayMode: .name,
        menuBarLabelPosition: .rightOfCenter,
        globalHotkeyShortcut: "Command+Option+Space",
        notesOverlayHotkeyEnabled: false,
        notesOverlayHotkeyShortcut: "Command+Option+N",
        notesOverlayItemOpacity: 0.34,
        notesOverlayBackgroundOpacity: 0.58,
        notesOverlayHeightPixels: 64,
        autoLaunchAssignedApps: false,
        hudFadeInSeconds: 0,
        hudHoldSeconds: 0,
        hudScale: 1,
        hudBackgroundOpacity: 0.94,
        hudPosition: .right,
        hudShowsDesktopNumber: true
    )

    enum CodingKeys: String, CodingKey {
        case hudEnabled
        case hudDurationSeconds
        case hudFadeInSeconds, hudHoldSeconds, hudScale, hudBackgroundOpacity, hudPosition, hudShowsDesktopNumber
        case apiEnabled
        case globalHotkeyEnabled
        case onboardingCompleted
        case screenshotDirectoryPath
        case menuBarDisplayMode
        case menuBarLabelPosition
        case globalHotkeyShortcut
        case notesOverlayHotkeyEnabled
        case notesOverlayHotkeyShortcut
        case notesOverlayItemOpacity
        case notesOverlayBackgroundOpacity
        case notesOverlayHeightPixels
        case autoLaunchAssignedApps
    }

    init(
        hudEnabled: Bool,
        hudDurationSeconds: Double,
        apiEnabled: Bool,
        globalHotkeyEnabled: Bool,
        onboardingCompleted: Bool,
        screenshotDirectoryPath: String = Self.defaults.screenshotDirectoryPath,
        menuBarDisplayMode: MenuBarDisplayMode = Self.defaults.menuBarDisplayMode,
        menuBarLabelPosition: MenuBarLabelPosition = Self.defaults.menuBarLabelPosition,
        globalHotkeyShortcut: String = Self.defaults.globalHotkeyShortcut,
        notesOverlayHotkeyEnabled: Bool = Self.defaults.notesOverlayHotkeyEnabled,
        notesOverlayHotkeyShortcut: String = Self.defaults.notesOverlayHotkeyShortcut,
        notesOverlayItemOpacity: Double = Self.defaults.notesOverlayItemOpacity,
        notesOverlayBackgroundOpacity: Double = Self.defaults.notesOverlayBackgroundOpacity,
        notesOverlayHeightPixels: Double = Self.defaults.notesOverlayHeightPixels,
        autoLaunchAssignedApps: Bool = Self.defaults.autoLaunchAssignedApps,
        hudFadeInSeconds: Double = Self.defaults.hudFadeInSeconds,
        hudHoldSeconds: Double = Self.defaults.hudHoldSeconds,
        hudScale: Double = Self.defaults.hudScale,
        hudBackgroundOpacity: Double = Self.defaults.hudBackgroundOpacity,
        hudPosition: HUDPosition = Self.defaults.hudPosition,
        hudShowsDesktopNumber: Bool = Self.defaults.hudShowsDesktopNumber
    ) {
        self.hudEnabled = hudEnabled
        self.hudDurationSeconds = hudDurationSeconds
        self.hudFadeInSeconds = hudFadeInSeconds
        self.hudHoldSeconds = hudHoldSeconds
        self.hudScale = hudScale
        self.hudBackgroundOpacity = hudBackgroundOpacity
        self.hudPosition = hudPosition
        self.hudShowsDesktopNumber = hudShowsDesktopNumber
        self.apiEnabled = apiEnabled
        self.globalHotkeyEnabled = globalHotkeyEnabled
        self.onboardingCompleted = onboardingCompleted
        self.screenshotDirectoryPath = screenshotDirectoryPath
        self.menuBarDisplayMode = menuBarDisplayMode
        self.menuBarLabelPosition = menuBarLabelPosition
        self.globalHotkeyShortcut = globalHotkeyShortcut
        self.notesOverlayHotkeyEnabled = notesOverlayHotkeyEnabled
        self.notesOverlayHotkeyShortcut = notesOverlayHotkeyShortcut
        self.notesOverlayItemOpacity = notesOverlayItemOpacity
        self.notesOverlayBackgroundOpacity = notesOverlayBackgroundOpacity
        self.notesOverlayHeightPixels = notesOverlayHeightPixels
        self.autoLaunchAssignedApps = autoLaunchAssignedApps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hudEnabled = try container.decodeIfPresent(Bool.self, forKey: .hudEnabled) ?? Self.defaults.hudEnabled
        hudDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .hudDurationSeconds) ?? Self.defaults.hudDurationSeconds
        hudFadeInSeconds = try container.decodeIfPresent(Double.self, forKey: .hudFadeInSeconds) ?? Self.defaults.hudFadeInSeconds
        hudHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .hudHoldSeconds) ?? Self.defaults.hudHoldSeconds
        hudScale = try container.decodeIfPresent(Double.self, forKey: .hudScale) ?? Self.defaults.hudScale
        hudBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .hudBackgroundOpacity) ?? Self.defaults.hudBackgroundOpacity
        let rawHUDPosition = try container.decodeIfPresent(String.self, forKey: .hudPosition)
        hudPosition = rawHUDPosition.flatMap(HUDPosition.init(rawValue:)) ?? Self.defaults.hudPosition
        hudShowsDesktopNumber = try container.decodeIfPresent(Bool.self, forKey: .hudShowsDesktopNumber) ?? Self.defaults.hudShowsDesktopNumber
        apiEnabled = try container.decodeIfPresent(Bool.self, forKey: .apiEnabled) ?? Self.defaults.apiEnabled
        globalHotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalHotkeyEnabled) ?? Self.defaults.globalHotkeyEnabled
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? Self.defaults.onboardingCompleted
        screenshotDirectoryPath = try container.decodeIfPresent(String.self, forKey: .screenshotDirectoryPath) ?? Self.defaults.screenshotDirectoryPath
        let rawMenuBarDisplayMode = try container.decodeIfPresent(String.self, forKey: .menuBarDisplayMode)
        menuBarDisplayMode = rawMenuBarDisplayMode.flatMap(MenuBarDisplayMode.init(rawValue:)) ?? Self.defaults.menuBarDisplayMode
        let rawMenuBarLabelPosition = try container.decodeIfPresent(String.self, forKey: .menuBarLabelPosition)
        menuBarLabelPosition = rawMenuBarLabelPosition.flatMap(MenuBarLabelPosition.init(rawValue:)) ?? Self.defaults.menuBarLabelPosition
        globalHotkeyShortcut = try container.decodeIfPresent(String.self, forKey: .globalHotkeyShortcut) ?? Self.defaults.globalHotkeyShortcut
        notesOverlayHotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .notesOverlayHotkeyEnabled) ?? Self.defaults.notesOverlayHotkeyEnabled
        notesOverlayHotkeyShortcut = try container.decodeIfPresent(String.self, forKey: .notesOverlayHotkeyShortcut) ?? Self.defaults.notesOverlayHotkeyShortcut
        notesOverlayItemOpacity = try container.decodeIfPresent(Double.self, forKey: .notesOverlayItemOpacity) ?? Self.defaults.notesOverlayItemOpacity
        notesOverlayBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .notesOverlayBackgroundOpacity) ?? Self.defaults.notesOverlayBackgroundOpacity
        notesOverlayHeightPixels = try container.decodeIfPresent(Double.self, forKey: .notesOverlayHeightPixels) ?? Self.defaults.notesOverlayHeightPixels
        autoLaunchAssignedApps = try container.decodeIfPresent(Bool.self, forKey: .autoLaunchAssignedApps) ?? Self.defaults.autoLaunchAssignedApps
    }

    var normalized: AppSettings {
        var copy = self
        func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        copy.hudDurationSeconds = bounded(copy.hudDurationSeconds, 0.2...10, fallback: Self.defaults.hudDurationSeconds)
        copy.hudFadeInSeconds = bounded(copy.hudFadeInSeconds, 0...3, fallback: Self.defaults.hudFadeInSeconds)
        copy.hudHoldSeconds = bounded(copy.hudHoldSeconds, 0...10, fallback: Self.defaults.hudHoldSeconds)
        copy.hudScale = bounded(copy.hudScale, 0.7...1.5, fallback: Self.defaults.hudScale)
        copy.hudBackgroundOpacity = bounded(copy.hudBackgroundOpacity, 0.15...1, fallback: Self.defaults.hudBackgroundOpacity)
        copy.screenshotDirectoryPath = copy.screenshotDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.globalHotkeyShortcut = copy.globalHotkeyShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        if KeyboardShortcut.parse(copy.globalHotkeyShortcut) == nil {
            copy.globalHotkeyShortcut = Self.defaults.globalHotkeyShortcut
        }
        copy.notesOverlayHotkeyShortcut = copy.notesOverlayHotkeyShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        if KeyboardShortcut.parse(copy.notesOverlayHotkeyShortcut) == nil {
            copy.notesOverlayHotkeyShortcut = Self.defaults.notesOverlayHotkeyShortcut
        }
        copy.notesOverlayItemOpacity = min(max(copy.notesOverlayItemOpacity, 0.12), 0.90)
        copy.notesOverlayBackgroundOpacity = min(max(copy.notesOverlayBackgroundOpacity, 0), 1)
        copy.notesOverlayHeightPixels = min(
            max(copy.notesOverlayHeightPixels, Self.minimumNotesOverlayHeightPixels),
            Self.maximumNotesOverlayHeightPixels
        )
        return copy
    }
}

enum HUDPosition: String, Codable, CaseIterable, Equatable {
    case right, center, left, top, bottom

    var label: String {
        switch self {
        case .right: "Right"
        case .center: "Center"
        case .left: "Left"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}

enum MenuBarLabelPosition: String, Codable, CaseIterable, Equatable {
    case hidden
    case center
    case rightOfCenter
    case farRight

    var label: String {
        switch self {
        case .hidden:
            "Hidden"
        case .center:
            "Center"
        case .rightOfCenter:
            "Right of Center"
        case .farRight:
            "Far Right"
        }
    }
}

enum MenuBarDisplayMode: String, Codable, CaseIterable, Equatable {
    case name
    case numberAndName
    case iconAndName
    case compact

    var label: String {
        switch self {
        case .name:
            "Desktop Name"
        case .numberAndName:
            "Badge + Desktop Name"
        case .iconAndName:
            "Icon + Desktop Name"
        case .compact:
            "Compact Badge"
        }
    }
}

struct DetectedSpace: Equatable {
    var stableID: String?
    var orderIndex: Int
}

struct SpaceDetectionSnapshot: Equatable {
    var spaces: [DetectedSpace]
    var activeOrderIndex: Int?
    var displaySnapshots: [DisplaySpaceSnapshot]
    var displayResolutions: [SpaceDisplayResolution]
    var source: String
    var eventDescription: String
    var date: Date
    var diagnostics: SpaceDetectionDiagnostics
}

struct DisplaySpaceSnapshot: Equatable {
    var displayIdentifier: String?
    var displayID: CGDirectDisplayID?
    var screenName: String?
    var frame: CGRect?
    var screenMatch: String
    var spaces: [DetectedSpace]
    var currentStableID: String?
    var activeOrderIndex: Int?
    var source: String
}

struct SpaceDisplayResolution: Equatable {
    var screenName: String?
    var displayID: CGDirectDisplayID?
    var dockDisplayIdentifier: String?
    var screenMatch: String
    var resolvedOrderIndex: Int?
    var source: String
    var confidence: DetectionConfidence
    var visibleWindowIDCount: Int
    var uniqueVisibleWindowIDCount: Int
    var ignoredSharedVisibleWindowIDCount: Int
    var dockCurrentStableID: String?
    var dockResolvedOrderIndex: Int?
    var windowMatchedOrderIndex: Int?
    var windowMatchCandidates: [SpaceWindowMatch]
    var fullscreenSpace: SpaceMetadata? = nil
}

struct NotesOverlayDisplaySummary: Equatable {
    var screenName: String?
    var displayID: CGDirectDisplayID?
    var screenMatch: String
    var source: String
    var fallbackUsed: Bool
    var spaces: [SpaceMetadata]
}

struct SpaceDetectionDiagnostics: Equatable {
    var confidence: DetectionConfidence
    var dockSpaceCount: Int
    var dockMonitorCount: Int
    var dockCurrentStableID: String?
    var dockCurrentStableIDs: [String]
    var dockActiveOrderIndex: Int?
    var visibleWindowIDCount: Int
    var uniqueVisibleWindowIDCount: Int
    var ignoredSharedVisibleWindowIDCount: Int
    var spaceWindowPropertyCount: Int
    var windowMatchedOrderIndex: Int?
    var windowMatchCandidates: [SpaceWindowMatch]
    var notes: [String]
}

enum DetectionConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
    case fallback
}

struct SpaceWindowMatch: Equatable {
    var stableID: String
    var orderIndex: Int
    var matchedVisibleWindowCount: Int
    var knownWindowCount: Int
}

struct ScannedWindow: Equatable {
    var appName: String
    var title: String
    var screenName: String
    var bounds: CGRect
}

struct RuleSuggestionSnapshot: Equatable {
    var generatedAt: Date
    var matches: [RuleMatch]
    var unassignedVisibleApps: [String]
    var duplicateAssignments: [String: [Int]]
}

struct RuleMatch: Equatable {
    var appName: String
    var spaceOrderIndex: Int
    var spaceName: String
    var windowCount: Int
}

struct DebugState: Equatable {
    var activeSpace: Int
    var detectionSource: String
    var lastDetectionEvent: String
    var lastSwitchAttempt: String
    var accessibilityTrusted: Bool
    var knownSpaces: [SpaceMetadata]
    var configURL: URL
}

enum SpaceNameBindingMode: String, Equatable {
    case stableID = "stable-id"
    case orderFallback = "order-fallback"

    var label: String {
        switch self {
        case .stableID:
            "Stable ID"
        case .orderFallback:
            "Order fallback"
        }
    }
}

struct SpaceNameBindingSummary: Equatable {
    var orderIndex: Int
    var displayName: String
    var stableID: String?
    var mode: SpaceNameBindingMode
    var rememberedStableIDCount: Int
    var repairCandidateName: String?
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if cleaned.count == 6 {
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
        } else {
            red = 0.18
            green = 0.50
            blue = 0.93
        }
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#2F80ED" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
