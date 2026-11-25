import Carbon.HIToolbox

@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard handlerStatus == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x434C_5348), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }
}
