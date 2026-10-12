import Foundation
import Combine
import WidgetKit

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [WorkNote] = []
    @Published var errorMessage: String?
    private let fileURL: URL
    private var canWrite = true
    private let publishesWidgets: Bool
    var orderedNotes: [WorkNote] { orderedCache }
    private var orderedCache: [WorkNote] = []
    private let writer = DispatchQueue(label: "it.massimopozzi.postit.persistence", qos: .utility)
    private var pendingEdits: [UUID: WorkNote] = [:]
    private var editTask: Task<Void, Never>?
    @Published var editRequest: WorkNote?
    private var widgetRefreshTask: Task<Void, Never>?
    // Notes changed outside the panel (the widget's "Fatto"); open cards replace their drafts.
    let externalUpdates = PassthroughSubject<WorkNote, Never>()

    init(fileURL: URL? = nil) {
        publishesWidgets = fileURL == nil
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DoveSonoArrivato", isDirectory: true)
            .appendingPathComponent("notes.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                notes = WorkNote.ordered(try JSONDecoder().decode([WorkNote].self, from: Data(contentsOf: self.fileURL)))
                for index in notes.indices { notes[index].sortPosition = index }
            }
            orderedCache = WorkNote.ordered(notes)
        } catch {
            canWrite = false
            errorMessage = L("Non riesco a leggere le note salvate. Il file originale è stato conservato in \(self.fileURL.path).",
                             "Your saved notes can’t be read. The original file was kept at \(self.fileURL.path).") + " \(error.localizedDescription)"
        }
    }

    // Reading a card must include edits still waiting for the debounce timer.
    // Rapid close/reopen and widget links must not restore an older copy.
    func currentNote(id: UUID) -> WorkNote? {
        pendingEdits[id] ?? notes.first { $0.id == id }
    }

    // The native editor updates immediately; disk work is coalesced after a short pause.
    func stageAutosave(_ note: WorkNote) -> Bool {
        guard canWrite else {
            errorMessage = L("Il file delle note non è leggibile. Le modifiche restano aperte nel pannello.",
                             "The notes file can’t be read. Your changes stay open in the panel.")
            return false
        }
        var updated = note
        updated.updatedAt = Date()
        updated.sortPosition = notes.first(where: { $0.id == note.id })?.sortPosition
            ?? ((notes.compactMap(\.sortPosition).min() ?? 0) - 1)
        pendingEdits[note.id] = updated
        if !notes.contains(where: { $0.id == note.id }) {
            publish(notes + [updated])
        }
        editTask?.cancel()
        editTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self else { return }
            let candidate = self.consumePendingEdits()
            self.publish(candidate)
            let file = self.fileURL
            self.writer.async { [weak self] in
                do { try Self.write(candidate, to: file) }
                catch {
                    let message = error.localizedDescription
                    Task { @MainActor [weak self] in
                        self?.errorMessage = L("Salvataggio non riuscito. Le modifiche restano nel pannello:",
                                               "Saving failed. Your changes stay in the panel:") + " \(message)"
                    }
                }
            }
            self.scheduleWidgetRefresh()
        }
        return true
    }

    // Drain earlier background writes before closing or performing a discrete action.
    @discardableResult
    func flushPendingEdits() -> Bool {
        editTask?.cancel()
        let edits = pendingEdits
        let success = persist(consumePendingEdits(), publishWidgets: false)
        if !success { pendingEdits.merge(edits) { _, latest in latest } }
        return success
    }

    private func consumePendingEdits() -> [WorkNote] {
        let candidate = notes.map { pendingEdits[$0.id] ?? $0 }
        pendingEdits.removeAll()
        return candidate
    }

    private func publish(_ candidate: [WorkNote]) {
        guard notes != candidate else { return }
        orderedCache = WorkNote.ordered(candidate)
        notes = candidate
    }

    private func scheduleWidgetRefresh() {
        widgetRefreshTask?.cancel()
        widgetRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.refreshWidgets()
        }
    }

    func save(_ note: WorkNote) -> Bool {
        guard pendingEdits.isEmpty || flushPendingEdits() else { return false }
        var updated = note
        updated.title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.title.isEmpty else { return false }
        updated.updatedAt = Date()
        var candidate = notes
        if let index = candidate.firstIndex(where: { $0.id == updated.id }) {
            updated.sortPosition = candidate[index].sortPosition
            candidate[index] = updated
        } else {
            updated.sortPosition = (notes.compactMap(\.sortPosition).min() ?? 0) - 1
            candidate.append(updated)
        }
        return persist(candidate)
    }

    // Persist every edit immediately, including an unfinished or temporarily empty title.
    func autosave(_ note: WorkNote) -> Bool {
        guard pendingEdits.isEmpty || flushPendingEdits() else { return false }
        var updated = note
        updated.updatedAt = Date()
        var candidate = notes
        if let index = candidate.firstIndex(where: { $0.id == updated.id }) {
            updated.sortPosition = candidate[index].sortPosition
            candidate[index] = updated
        } else {
            updated.sortPosition = (notes.compactMap(\.sortPosition).min() ?? 0) - 1
            candidate.append(updated)
        }
        guard persist(candidate, publishWidgets: false) else { return false }
        scheduleWidgetRefresh()
        return true
    }

    func reorder(_ ids: [UUID]) -> Bool {
        guard pendingEdits.isEmpty || flushPendingEdits() else { return false }
        let selected = Set(ids)
        guard selected.count == ids.count, ids.count > 1,
              selected.isSubset(of: Set(notes.map(\.id))) else { return false }
        var candidate = orderedNotes
        let replacements = ids.compactMap { id in notes.first { $0.id == id } }
        var next = 0
        for index in candidate.indices where selected.contains(candidate[index].id) {
            candidate[index] = replacements[next]
            next += 1
        }
        for index in candidate.indices { candidate[index].sortPosition = index }
        return persist(candidate)
    }

    func setCompleted(_ note: WorkNote, completed: Bool) -> Bool {
        var updated = note
        updated.completedAt = completed ? Date() : nil
        return save(updated)
    }

    // Apply "Fatto" presses queued by the widget, oldest first. A file stays queued
    // only if saving fails, so it is retried on the next launch or notification.
    @discardableResult
    func applyWidgetActions(from directory: URL? = WidgetActions.directory) -> Int {
        guard canWrite else { return 0 }
        let pending = WidgetActions.pending(in: directory)
        guard !pending.isEmpty else { return 0 }
        var applied = 0
        for (file, action) in pending {
            if var note = currentNote(id: action.noteID), note.trimmedNextStep == action.step,
               note.advanceStep(at: action.date) {
                guard autosave(note) else { break }
                externalUpdates.send(currentNote(id: note.id) ?? note)
                applied += 1
            }
            WidgetActions.remove(file)
        }
        // The widget showed its change optimistically; republish the app's truth either way.
        refreshWidgets()
        return applied
    }

    func refreshWidgets(waitForWrite: Bool = false) {
        guard canWrite && publishesWidgets else { return }
        let snapshot = notes
        let writeSnapshot: @Sendable () -> Void = {
            do {
                try WidgetSnapshot.write(snapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
            } catch {
                NSLog("Widget snapshot unavailable: %@", error.localizedDescription)
            }
        }
        if waitForWrite { writer.sync(execute: writeSnapshot) }
        else { writer.async(execute: writeSnapshot) }
    }

    private func persist(_ candidate: [WorkNote], publishWidgets: Bool = true) -> Bool {
        guard canWrite else {
            errorMessage = L("Il file delle note non è leggibile. Recupera il file originale prima di salvare nuove note.",
                             "The notes file can’t be read. Recover the original file before saving new notes.")
            return false
        }
        do {
            try writer.sync { try Self.write(candidate, to: fileURL) }
            publish(candidate)
            if publishWidgets { refreshWidgets() }
            return true
        } catch {
            errorMessage = L("Salvataggio non riuscito. La nota resta aperta:", "Saving failed. The note stays open:")
                + " \(error.localizedDescription)"
            return false
        }
    }

    nonisolated private static func write(_ candidate: [WorkNote], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(candidate).write(to: file, options: .atomic)
    }
}
