import XCTest
import Combine
@testable import DoveSonoArrivato

final class StepHistoryTests: XCTestCase {
    func testFattoArchivesThePreviousPointAndAdvances() {
        var note = WorkNote()
        note.progress = "Scritta la bozza"
        note.nextStep = "  Rileggere il capitolo \n"
        note.action = .waiting
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(note.advanceStep(at: date))
        XCTAssertEqual(note.progress, "Rileggere il capitolo")
        XCTAssertEqual(note.nextStep, "")
        XCTAssertEqual(note.action, .next)
        XCTAssertEqual(note.steps.map(\.text), ["Scritta la bozza"])
        XCTAssertEqual(note.steps.first?.date, date)
        // Nothing to advance: no change, no empty history entries.
        XCTAssertFalse(note.advanceStep())
        XCTAssertEqual(note.steps.count, 1)
    }

    func testEmptyProgressIsNotArchived() {
        var note = WorkNote()
        note.nextStep = "Primo passo"
        XCTAssertTrue(note.advanceStep())
        XCTAssertTrue(note.steps.isEmpty)
        XCTAssertNil(note.history)
    }

    func testNotesSavedByEarlierVersionsStillDecode() throws {
        let legacy = """
        [{"id":"6F1C2A44-2B7E-4B39-9A61-3E5E0C1E9A10","title":"Vecchia nota","progress":"Qui","action":"Prossimo passo",
          "nextStep":"Poi","conclusion":"","color":"yellow","updatedAt":700000000}]
        """
        let notes = try JSONDecoder().decode([WorkNote].self, from: Data(legacy.utf8))
        XCTAssertEqual(notes.first?.title, "Vecchia nota")
        XCTAssertEqual(notes.first?.steps, [])
    }

    @MainActor
    func testWidgetFattoIsAppliedOnceAndOnlyToTheStepItSaw() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes.json")
        let queue = root.appendingPathComponent("actions", isDirectory: true)
        let store = NoteStore(fileURL: file)
        var note = WorkNote(); note.title = "Lavoro"; note.progress = "Inizio"; note.nextStep = "Secondo passo"
        var other = WorkNote(); other.title = "Altro"; other.nextStep = "Passo cambiato nel frattempo"
        XCTAssertTrue(store.save(note)); XCTAssertTrue(store.save(other))
        var updates: [WorkNote] = []
        let subscription = store.externalUpdates.sink { updates.append($0) }
        defer { subscription.cancel() }

        try WidgetActions.enqueue(WidgetAdvanceAction(noteID: note.id, step: "Secondo passo", date: Date()), in: queue)
        // A stale press: the widget saw an older next step than the app has now.
        try WidgetActions.enqueue(WidgetAdvanceAction(noteID: other.id, step: "Vecchio passo", date: Date()), in: queue)
        XCTAssertEqual(store.applyWidgetActions(from: queue), 1)

        let saved = NoteStore(fileURL: file)
        XCTAssertEqual(saved.currentNote(id: note.id)?.progress, "Secondo passo")
        XCTAssertEqual(saved.currentNote(id: note.id)?.steps.map(\.text), ["Inizio"])
        XCTAssertEqual(saved.currentNote(id: other.id)?.nextStep, "Passo cambiato nel frattempo")
        XCTAssertEqual(updates.map(\.id), [note.id])
        XCTAssertTrue(WidgetActions.pending(in: queue).isEmpty)
        // The queue is drained: a second notification changes nothing.
        XCTAssertEqual(store.applyWidgetActions(from: queue), 0)
    }
}
