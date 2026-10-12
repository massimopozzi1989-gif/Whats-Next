import AppKit

// The panel's window undo manager, shared with the native text editors, so ⌘Z walks
// typing and card actions (Fatto, colour, completion…) in one history.
@MainActor
enum PanelUndo {
    private final class Target {}
    private static let target = Target()
    static var managerOverride: UndoManager?

    static var manager: UndoManager? {
        managerOverride ?? NSApp.windows.first { $0 is NotesPanel }?.undoManager
    }

    // The handler runs on undo; it must register its own inverse to support redo.
    static func register(_ name: String, _ handler: @escaping () -> Void) {
        guard let manager else { return }
        manager.registerUndo(withTarget: target) { _ in handler() }
        manager.setActionName(name)
    }

    // Undo restores the earlier snapshot of the card, redo the later one.
    static func registerNote(_ name: String, restore: WorkNote, redo: WorkNote, apply: @escaping (WorkNote) -> Void) {
        register(name) {
            apply(restore)
            registerNote(name, restore: redo, redo: restore, apply: apply)
        }
    }

    // Editors that leave the screen take their typing history with them; never let
    // ⌘Z reach text views that no longer exist.
    static func reset() {
        manager?.removeAllActions()
    }
}
