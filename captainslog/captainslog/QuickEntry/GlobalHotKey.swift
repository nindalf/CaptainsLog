import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "quickentry")

/// A system-wide shortcut. Carbon's `RegisterEventHotKey` is still the only API for this that needs
/// no Accessibility permission. Call `unregister` before dropping it.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// `keyCode` is a `kVK_` virtual key, `modifiers` a mask of Carbon's `controlKey`, `cmdKey` and so on.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated {
                    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard status == noErr else {
            logger.error("InstallEventHandler failed: \(status)")
            return nil
        }
        let id = EventHotKeyID(signature: OSType(0x434C_4F47), id: 1) // "CLOG"
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            logger.error("RegisterEventHotKey failed: \(registered)")
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
