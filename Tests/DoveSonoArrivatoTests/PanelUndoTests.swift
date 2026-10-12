import XCTest
import AppKit
@testable import DoveSonoArrivato

final class PanelUndoTests: XCTestCase {
    @MainActor
    func testFattoUndoRestoresProgressAndRedoAdvancesAgain() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        PanelUndo.managerOverride = manager
        defer { PanelUndo.managerOverride = nil }

        var note = WorkNote()
        note.progress = "Bozza scritta"
        note.nextStep = "Rileggere il capitolo"
        note.action = .waiting
        var advanced = note
        advanced.progress = "Rileggere il capitolo"
        advanced.nextStep = ""
        advanced.action = .next

        var shown = advanced
        manager.beginUndoGrouping()
        PanelUndo.registerNote("Fatto", restore: note, redo: advanced) { shown = $0 }
        manager.endUndoGrouping()
        XCTAssertEqual(manager.undoActionName, "Fatto")

        manager.undo()
        XCTAssertEqual(shown, note)
        XCTAssertTrue(manager.canRedo)
        manager.redo()
        XCTAssertEqual(shown, advanced)
        manager.undo()
        XCTAssertEqual(shown, note)

        PanelUndo.reset()
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
    }

    @MainActor
    func testCommandZOnThePanelUndoesAndRedoesTyping() throws {
        let panel = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let field = PaperTextView(usingTextLayoutManager: false)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        field.allowsUndo = true
        panel.contentView = field
        XCTAssertTrue(panel.makeFirstResponder(field))
        field.undoManager?.groupsByEvent = false
        field.undoManager?.beginUndoGrouping()
        field.insertText("Dove sono arrivato", replacementRange: NSRange(location: 0, length: 0))
        field.undoManager?.endUndoGrouping()
        XCTAssertEqual(field.string, "Dove sono arrivato")

        func key(_ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: panel.windowNumber, context: nil, characters: characters,
                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 6)!
        }
        XCTAssertTrue(panel.performKeyEquivalent(with: key("z", .command)))
        XCTAssertEqual(field.string, "")
        XCTAssertTrue(panel.performKeyEquivalent(with: key("Z", [.command, .shift])))
        XCTAssertEqual(field.string, "Dove sono arrivato")
    }
}
