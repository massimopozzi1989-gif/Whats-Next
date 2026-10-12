import Carbon

@MainActor
final class PanelShortcut {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    init(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<PanelShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcut.action() }
            return noErr
        }, 1, &event, context, &handler)
        guard result == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x44534150, id: 1)
        isRegistered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier,
                                            GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
