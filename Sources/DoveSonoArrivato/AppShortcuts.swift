import AppIntents
import Foundation

struct AppNoteEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lavoro")
    static var defaultQuery = AppNoteQuery()
    var id: String
    var title: String
    var progress: String
    var nextStep: String
    var displayRepresentation: DisplayRepresentation {
        let subtitle = nextStep.isEmpty ? progress : nextStep
        return DisplayRepresentation(title: "\(title.isEmpty ? L("Nuovo lavoro", "New note") : title)",
                                     subtitle: subtitle.isEmpty ? nil : "\(subtitle)")
    }

    init(note: WorkNote) {
        self.id = note.id.uuidString
        self.title = note.title
        self.progress = note.progress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nextStep = note.trimmedNextStep
    }
}

struct AppNoteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AppNoteEntity] {
        await MainActor.run {
            let store = NoteStore.shared ?? NoteStore()
            return store.orderedNotes
                .filter { identifiers.contains($0.id.uuidString) }
                .map(AppNoteEntity.init(note:))
        }
    }

    func suggestedEntities() async throws -> [AppNoteEntity] {
        await MainActor.run {
            let store = NoteStore.shared ?? NoteStore()
            return WorkNote.priorityFirst(store.orderedNotes)
                .filter { $0.completedAt == nil }
                .map(AppNoteEntity.init(note:))
        }
    }
}

struct CreatePostItIntent: AppIntent {
    static var title: LocalizedStringResource = "Crea post-it"
    static var description = IntentDescription("Crea un nuovo post-it in What’s Next? con titolo, dove sei arrivato e prossimo passo.")
    static var openAppWhenRun = false

    @Parameter(title: "Titolo") var title: String
    @Parameter(title: "Dove sono arrivato", default: "") var progress: String
    @Parameter(title: "Prossimo passo", default: "") var nextStep: String
    @Parameter(title: "Priorità", default: false) var priority: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<AppNoteEntity> {
        let store = NoteStore.shared ?? NoteStore()
        var note = WorkNote()
        note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        note.progress = progress
        note.nextStep = nextStep
        note.priority = priority ? true : nil
        note.color = PaperColor(rawValue: UserDefaults.standard.string(forKey: "defaultPaperColor") ?? "yellow") ?? .yellow
        _ = store.autosave(note)
        store.refreshWidgets(force: true)
        return .result(value: AppNoteEntity(note: note))
    }
}

struct CompleteStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Segna passo fatto"
    static var description = IntentDescription("Sposta il prossimo passo in “Dove sono arrivato” sul post-it scelto.")
    static var openAppWhenRun = false

    @Parameter(title: "Lavoro") var note: AppNoteEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = NoteStore.shared ?? NoteStore()
        guard let id = UUID(uuidString: note.id),
              var target = store.currentNote(id: id),
              target.advanceStep() else {
            return .result(value: L("Nessun prossimo passo da completare.", "No next step to mark done."))
        }
        _ = store.autosave(target)
        store.externalUpdates.send(target)
        store.refreshWidgets(force: true)
        return .result(value: target.progress)
    }
}

struct WhatsNextStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Dove sono arrivato?"
    static var description = IntentDescription("Legge dove sei arrivato e qual è il prossimo passo per un lavoro.")
    static var openAppWhenRun = false

    @Parameter(title: "Lavoro") var note: AppNoteEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = NoteStore.shared ?? NoteStore()
        guard let id = UUID(uuidString: note.id),
              let target = store.currentNote(id: id) else {
            return .result(value: "")
        }
        return .result(value: target.formattedText())
    }
}

struct WhatsNextShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreatePostItIntent(),
            phrases: [
                "Nuovo post-it in \(.applicationName)",
                "New note in \(.applicationName)"
            ],
            shortTitle: "Nuovo post-it",
            systemImageName: "note.text.badge.plus"
        )
        AppShortcut(
            intent: WhatsNextStatusIntent(),
            phrases: [
                "Dove sono arrivato in \(.applicationName)",
                "What's next in \(.applicationName)"
            ],
            shortTitle: "Dove sono arrivato",
            systemImageName: "note.text"
        )
    }
}
