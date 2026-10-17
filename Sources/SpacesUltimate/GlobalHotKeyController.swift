import AppKit
import ApplicationServices
import Carbon

@MainActor
final class GlobalHotKeyController {
    private var eventHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void
    private let logName: String
    private var shortcut = KeyboardShortcut.parse(AppSettings.defaults.globalHotkeyShortcut)!
    private let hotKeyID: UInt32
    private static var nextHotKeyID: UInt32 = 1
    private(set) var isRegistered = false

    init(logName: String = "overview", action: @escaping () -> Void) {
        self.logName = logName
        self.action = action
        self.hotKeyID = Self.nextHotKeyID
        Self.nextHotKeyID += 1
    }

    func register(shortcut shortcutText: String = AppSettings.defaults.globalHotkeyShortcut) {
        unregister()
        shortcut = KeyboardShortcut.parse(shortcutText) ?? KeyboardShortcut.parse(AppSettings.defaults.globalHotkeyShortcut)!

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var eventID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventID
                )
                guard status == noErr else { return status }

                let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                guard eventID.signature == GlobalHotKeyController.signature, eventID.id == controller.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }
                Task { @MainActor in controller.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            AppLog.shared.error("Failed to install \(logName) hotkey handler: \(handlerStatus)")
            return
        }

        let carbonHotKeyID = EventHotKeyID(signature: Self.signature, id: hotKeyID)
        let registerStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            carbonHotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )
        if registerStatus == noErr {
            isRegistered = true
            AppLog.shared.info("Registered global \(logName) hotkey \(shortcut.displayName)")
        } else {
            AppLog.shared.error("Failed to register global \(logName) hotkey \(shortcut.displayName): \(registerStatus)")
            unregister()
        }
    }

    func unregister() {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHotKey = nil
        eventHandler = nil
        isRegistered = false
    }

    private static let signature: OSType = {
        let scalars = Array("SpUl".unicodeScalars)
        return scalars.reduce(OSType(0)) { ($0 << 8) + OSType($1.value) }
    }()
}
