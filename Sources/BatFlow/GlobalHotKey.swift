import Carbon.HIToolbox
import AppKit

/// System-wide hotkey via Carbon's RegisterEventHotKey. Unlike an NSEvent global
/// monitor this needs no Accessibility permission and costs nothing while idle.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// ⌃⌥N. Plain ⌥N is the dead key for ñ/ã/õ on US and ABC layouts.
    nonisolated static let defaultKeyCode = UInt32(kVK_ANSI_N)
    nonisolated static let defaultModifiers = UInt32(controlKey | optionKey)
    nonisolated static let displayString = "⌃⌥N"

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register(keyCode: UInt32 = defaultKeyCode, modifiers: UInt32 = defaultModifiers) {
        unregister()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &handlerRef
        )

        let id = EventHotKeyID(signature: OSType(0x4246_4C57), id: 1) // "BFLW"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
