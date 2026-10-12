import XCTest
@testable import DoveSonoArrivato

final class NoteStoreTests: XCTestCase {
    @MainActor
    func testImmediateReopenReadsPendingEditsWithoutWaitingForDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = NoteStore(fileURL: file)
        var first = WorkNote(); first.title = "Prima card"
        var second = WorkNote(); second.title = "Seconda card"
        XCTAssertTrue(store.save(first)); XCTAssertTrue(store.save(second))
        first.progress = "Ultima frase prima di chiudere "
        first.title = "Titolo modificato"
        XCTAssertTrue(store.stageAutosave(first))
        second.nextStep = "Passaggio appena scritto"
        XCTAssertTrue(store.stageAutosave(second))
        // Disk is still the previous snapshot: reopening must read pending edits instead.
        XCTAssertEqual(NoteStore(fileURL: file).currentNote(id: first.id)?.title, "Prima card")
        XCTAssertEqual(store.currentNote(id: first.id)?.title, "Titolo modificato")
        XCTAssertEqual(store.currentNote(id: first.id)?.progress, first.progress)
        XCTAssertEqual(store.currentNote(id: second.id)?.nextStep, second.nextStep)
        XCTAssertTrue(store.flushPendingEdits())
        XCTAssertEqual(NoteStore(fileURL: file).currentNote(id: first.id)?.progress, first.progress)
    }

    @MainActor
    func testTypingBurstCoalescesWithoutPublishingEveryCharacterAndFlushesOnClose() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = NoteStore(fileURL: file)
        var publications = 0
        let subscription = store.$notes.sink { _ in publications += 1 }
        defer { subscription.cancel() }
        var note = WorkNote()
        for index in 0..<500 {
            note.progress = "Testo \(index) "
            XCTAssertTrue(store.stageAutosave(note))
        }
        XCTAssertEqual(publications, 2) // Initial subscription + new note, not 500 updates.
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(store.flushPendingEdits())
        XCTAssertEqual(NoteStore(fileURL: file).notes.first?.progress, "Testo 499 ")
        XCTAssertEqual(publications, 3)
    }

    @MainActor
    func testBackgroundAutosaveCannotOverwriteLaterCompletionOrOrdering() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = NoteStore(fileURL: file)
        var first = WorkNote(); first.title = "Primo"
        var second = WorkNote(); second.title = "Secondo"
        XCTAssertTrue(store.save(first)); XCTAssertTrue(store.save(second))
        first.progress = "Automatico"
        XCTAssertTrue(store.stageAutosave(first))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(NoteStore(fileURL: file).notes.first { $0.id == first.id }?.progress, "Automatico")
        first.progress = "Ultimo testo"
        XCTAssertTrue(store.stageAutosave(first))
        XCTAssertTrue(store.reorder([first.id, second.id]))
        XCTAssertTrue(store.setCompleted(store.notes.first { $0.id == first.id }!, completed: true))
        try await Task.sleep(for: .milliseconds(300))
        let reloaded = NoteStore(fileURL: file)
        XCTAssertEqual(reloaded.orderedNotes.map(\.id), [first.id, second.id])
        XCTAssertEqual(reloaded.notes.first { $0.id == first.id }?.progress, "Ultimo testo")
        XCTAssertNotNil(reloaded.notes.first { $0.id == first.id }?.completedAt)
    }

    @MainActor
    func testFailedFlushPreservesPendingTextForRetry() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = NoteStore(fileURL: file)
        var note = WorkNote(); note.title = "Lavoro"
        XCTAssertTrue(store.save(note))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        note.progress = "Da conservare"
        XCTAssertTrue(store.stageAutosave(note))
        XCTAssertFalse(store.flushPendingEdits())
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(store.flushPendingEdits())
        XCTAssertEqual(NoteStore(fileURL: file).notes.first?.progress, "Da conservare")
    }

    @MainActor
    func testSaveReloadCompleteAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.json")
        let store = NoteStore(fileURL: file)
        var note = WorkNote()
        note.title = "  Sito cliente  "
        note.progress = "Homepage pronta"
        note.action = .waiting
        note.nextStep = "Conferma dei testi"
        note.workLink = "https://example.com/progetto"
        XCTAssertTrue(store.save(note))
        let reloaded = NoteStore(fileURL: file)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes[0].title, "Sito cliente")
        XCTAssertEqual(reloaded.notes[0].action, .waiting)
        XCTAssertEqual(reloaded.notes[0].workLink, "https://example.com/progetto")
        XCTAssertTrue(reloaded.setCompleted(reloaded.notes[0], completed: true))
        let completed = NoteStore(fileURL: file)
        XCTAssertNotNil(completed.notes[0].completedAt)
        XCTAssertTrue(completed.setCompleted(completed.notes[0], completed: false))
        XCTAssertNil(NoteStore(fileURL: file).notes[0].completedAt)
        note.progress = "Testi aggiornati"
        XCTAssertTrue(completed.save(note))
        XCTAssertEqual(completed.notes.count, 1)
        XCTAssertEqual(NoteStore(fileURL: file).notes[0].progress, "Testi aggiornati")
    }

    @MainActor
    func testAutosavePersistsEachEditIncludingAnUnfinishedTitle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.json")
        let store = NoteStore(fileURL: file)
        var note = WorkNote()
        note.progress = "Testo scritto prima del titolo"
        XCTAssertTrue(store.autosave(note))
        XCTAssertEqual(NoteStore(fileURL: file).notes.first?.progress, note.progress)
        note.title = "Titolo in corso "
        XCTAssertTrue(store.autosave(note))
        XCTAssertEqual(NoteStore(fileURL: file).notes.first?.title, "Titolo in corso ")
        note.title = ""
        note.progress = "Ultima modifica prima di chiudere"
        XCTAssertTrue(store.autosave(note))
        let reopened = NoteStore(fileURL: file)
        XCTAssertEqual(reopened.notes.count, 1)
        XCTAssertEqual(reopened.notes[0].title, "")
        XCTAssertEqual(reopened.notes[0].progress, note.progress)
    }

    @MainActor
    func testManualOrderSurvivesEditingAndRelaunch() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = NoteStore(fileURL: file)
        var first = WorkNote(); first.title = "Primo"
        var second = WorkNote(); second.title = "Secondo"
        var archived = WorkNote(); archived.title = "Completato"; archived.completedAt = Date()
        XCTAssertTrue(store.save(first)); XCTAssertTrue(store.save(archived)); XCTAssertTrue(store.save(second))
        XCTAssertTrue(store.reorder([first.id, second.id]))
        let order = store.orderedNotes.map(\.id)
        first.progress = "Un nuovo aggiornamento"
        XCTAssertTrue(store.autosave(first))
        XCTAssertEqual(store.orderedNotes.map(\.id), order)
        XCTAssertEqual(NoteStore(fileURL: file).orderedNotes.map(\.id), order)
        XCTAssertEqual(store.orderedNotes.filter { $0.completedAt == nil }.map(\.id), [first.id, second.id])
        XCTAssertTrue(store.reorder([second.id, first.id]))
        XCTAssertEqual(NoteStore(fileURL: file).orderedNotes.filter { $0.completedAt == nil }.map(\.id), [second.id, first.id])
        XCTAssertFalse(store.reorder([first.id, first.id]))
    }

    func testOldNotesWithoutLinkStillDecode() throws {
        var note = WorkNote()
        note.title = "Nota precedente"
        let encoded = try JSONEncoder().encode([note])
        let oldData = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        XCTAssertNil(oldData[0]["workLink"])
        let decoded = try JSONDecoder().decode([WorkNote].self, from: JSONSerialization.data(withJSONObject: oldData))
        XCTAssertEqual(decoded[0].title, "Nota precedente")
        XCTAssertNil(decoded[0].workLink)
    }

    func testWorkLinksPreserveFolderNamesAndValidateWebURLs() throws {
        let folder = try XCTUnwrap(WorkLink.url(for: "/Users/example/Un progetto con spazi"))
        XCTAssertTrue(folder.isFileURL)
        XCTAssertEqual(folder.path, "/Users/example/Un progetto con spazi")
        XCTAssertEqual(WorkLink.url(for: folder.absoluteString), folder)
        XCTAssertEqual(WorkLink.url(for: "www.example.com/progetto")?.scheme, "https")
        XCTAssertNil(WorkLink.url(for: "javascript:alert(1)"))
        XCTAssertNil(WorkLink.url(for: "https://"))
        XCTAssertNil(WorkLink.url(for: "non è un link"))
    }

    func testWidgetURLsRouteToTheCorrectPostIt() throws {
        let note = WorkNote()
        XCTAssertEqual(PanelRoute(url: WidgetSnapshot.link(note)), .note(note.id))
        XCTAssertEqual(PanelRoute(url: try XCTUnwrap(URL(string: "dovesonoarrivato://new"))), .new)
        XCTAssertEqual(PanelRoute(url: WidgetSnapshot.openPanel), .show)
        XCTAssertNil(PanelRoute(url: try XCTUnwrap(URL(string: "dovesonoarrivato://note/not-an-id"))))
        XCTAssertNil(PanelRoute(url: try XCTUnwrap(URL(string: "https://example.com/note/\(note.id)"))))
    }

    @MainActor
    func testCorruptFileIsNeverOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Data("non è JSON".utf8)
        try original.write(to: file)
        let store = NoteStore(fileURL: file)
        XCTAssertNotNil(store.errorMessage)
        var note = WorkNote()
        note.title = "Nuova nota"
        XCTAssertFalse(store.save(note))
        XCTAssertFalse(store.autosave(note))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor
    func testFailedWriteDoesNotChangeNotes() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.json")
        let store = NoteStore(fileURL: file)
        try? FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        var note = WorkNote()
        note.title = "Lavoro"
        XCTAssertFalse(store.save(note))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }
}
