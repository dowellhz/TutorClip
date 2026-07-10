import AppKit
import Carbon

struct ShortcutRegistrationResult: Equatable {
    var isRegistered: Bool
    var message: String

    static let unregistered = ShortcutRegistrationResult(isRegistered: false, message: "Shortcut is not registered yet.")
}

final class ShortcutManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let settings: AppSettings
    private let onTrigger: () -> Void

    init(settings: AppSettings, onTrigger: @escaping () -> Void) {
        self.settings = settings
        self.onTrigger = onTrigger
    }

    func register() -> ShortcutRegistrationResult {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onTrigger()
            return noErr
        }, 1, &eventType, selfPointer, &handlerRef)
        guard handlerStatus == noErr else {
            return ShortcutRegistrationResult(isRegistered: false, message: "Failed to install shortcut handler: \(handlerStatus).")
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x54544350), id: 1)
        let hotKeyStatus = RegisterEventHotKey(settings.shortcutKeyCode, settings.shortcutModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard hotKeyStatus == noErr else {
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
            return ShortcutRegistrationResult(isRegistered: false, message: "Failed to register \(settings.shortcutDisplay): \(hotKeyStatus).")
        }
        return ShortcutRegistrationResult(isRegistered: true, message: "Registered \(settings.shortcutDisplay).")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
