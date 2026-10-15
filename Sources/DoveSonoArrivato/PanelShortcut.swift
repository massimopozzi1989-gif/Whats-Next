import Carbon
import AppKit

struct ShortcutSpec: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultSpec = ShortcutSpec(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey))
    static let keyCodeKey = "panelShortcutKeyCode"
    static let modifiersKey = "panelShortcutModifiers"

    static func load(from defaults: UserDefaults = .standard) -> ShortcutSpec {
        guard defaults.object(forKey: keyCodeKey) != nil,
              defaults.object(forKey: modifiersKey) != nil else {
            return defaultSpec
        }
        return ShortcutSpec(
            keyCode: UInt32(defaults.integer(forKey: keyCodeKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: modifiersKey))
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(carbonModifiers), forKey: Self.modifiersKey)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyCodeKey)
        defaults.removeObject(forKey: modifiersKey)
    }

    static func from(event: NSEvent) -> ShortcutSpec? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Require at least one command/option/control modifier so plain typing is never captured.
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let ignoredKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // standalone modifiers
        guard !ignoredKeyCodes.contains(event.keyCode) else { return nil }
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return ShortcutSpec(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
    }

    var displayString: String {
        var parts = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { parts += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { parts += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { parts += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { parts += "⌘" }
        parts += Self.keyLabel(for: keyCode)
        return parts
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return L("Spazio", "Space")
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return "#\(keyCode)"
        }
    }
}

@MainActor
final class PanelShortcut {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: () -> Void
    private(set) var isRegistered = false
    private(set) var currentSpec: ShortcutSpec

    init(spec: ShortcutSpec = ShortcutSpec.load(), action: @escaping () -> Void) {
        self.action = action
        self.currentSpec = spec
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<PanelShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcut.action() }
            return noErr
        }, 1, &event, context, &handler)
        guard result == noErr else { return }
        _ = update(to: spec)
    }

    @discardableResult
    func update(to spec: ShortcutSpec) -> Bool {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        currentSpec = spec
        let identifier = EventHotKeyID(signature: 0x44534150, id: 1)
        isRegistered = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, identifier,
                                            GetApplicationEventTarget(), 0, &hotKey) == noErr
        UserDefaults.standard.set(isRegistered, forKey: "panelShortcutAvailable")
        return isRegistered
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
