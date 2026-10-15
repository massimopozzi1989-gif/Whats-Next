import SwiftUI
import AppKit

struct BoardView: View {
    @ObservedObject var store: NoteStore
    let hide: () -> Void
    let maxHeight: CGFloat
    let resize: (CGFloat) -> Void
    let beginReading: () -> Void
    @State private var notesHeight: CGFloat = 76
    @State private var completed = false
    @State private var drafts: [UUID: WorkNote] = [:]
    @State private var newNotes: [WorkNote] = []
    @State private var search = ""
    @State private var showsSearch = false
    @FocusState private var searchFocused: Bool
    @State private var expandedID: UUID?
    @State private var highlightedID: UUID?
    @State private var pendingDeletion: WorkNote?
    @AppStorage("defaultPaperColor") private var defaultPaperColor = PaperColor.yellow.rawValue
    @Environment(\.openSettings) private var openSettings
    @AppStorage("staleAfterDays") private var staleAfterDays = 7
    // Read so a language change in Settings redraws the panel at once.
    @AppStorage(AppLanguage.key) private var languagePreference = AppLanguage.system.rawValue

    private var visibleNotes: [WorkNote] {
        let saved = store.orderedNotes
        let trimmedQuery = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkNote.priorityFirst((newNotes + saved).map { drafts[$0.id] ?? $0 })
            .filter { ($0.completedAt != nil) == completed }
            .filter { note in
                guard !trimmedQuery.isEmpty, drafts[note.id] == nil else { return true }
                return "\(note.title) \(note.progress) \(note.nextStep) \(note.steps.map(\.text).joined(separator: " "))"
                    .localizedCaseInsensitiveContains(trimmedQuery)
            }
    }

    var body: some View {
        let displayedNotes = visibleNotes
        let newIDs = Set(newNotes.map(\.id))
        let now = Date()
        let language = AppLanguage.current
        let completedCount = store.notes.reduce(0) { $0 + ($1.completedAt != nil ? 1 : 0) }
        let activeCount = (store.notes.count - completedCount) + newNotes.count
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    Button(L("In corso", "In progress") + " · \(activeCount)") { showList(completed: false) }
                    Button(L("Completati", "Completed") + " · \(completedCount)") { showList(completed: true) }
                    Divider()
                    Button(showsSearch ? L("Nascondi ricerca (⌘F)", "Hide search (⌘F)") : L("Cerca un lavoro (⌘F)", "Search notes (⌘F)")) {
                        toggleSearch()
                    }
                    Button(L("Impostazioni…", "Settings…")) {
                        // The panel never activates the app; a real window needs it to come forward.
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                    Button(L("Mostra la cartella delle note", "Show notes folder")) {
                        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DoveSonoArrivato")
                        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    }
                    Divider()
                    Button(L("Esci da What’s Next?", "Quit What’s Next?")) { NSApp.terminate(nil) }
                } label: {
                    Label(completed ? L("Completati", "Completed") : L("In corso", "In progress"), systemImage: completed ? "checkmark.circle" : "note.text")
                        .font(.system(size: 12, weight: .medium))
                }.menuStyle(.borderlessButton).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 8).background(.regularMaterial, in: Capsule())
                Spacer()
                floatingButton(L("Nuovo post-it", "New note"), symbol: "plus", action: addNote)
                    .keyboardShortcut("n", modifiers: .command)
                floatingButton(L("Nascondi il pannello", "Hide panel"), symbol: "xmark", action: handleEscapeOrHide)
                    .keyboardShortcut(.escape, modifiers: [])
            }.padding(.horizontal, 14).padding(.top, 10)

            if showsSearch {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField(L("Cerca un lavoro", "Search notes"), text: $search)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onExitCommand { closeSearch() }
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").opacity(0.6) }
                            .buttonStyle(.plain)
                    }
                }.padding(10).background(.regularMaterial, in: Capsule()).padding(.horizontal, 14)
            }

            NativeBoardScrollView(selectedID: expandedID ?? highlightedID, contentHeightChanged: { notesHeight = $0 },
                                  moveNote: { source, target, after in move(source, relativeTo: target, after: after) }) {
                    VStack(spacing: -18) {
                        if displayedNotes.isEmpty {
                            Button(action: addNote) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(completed ? L("Nessun lavoro completato", "Nothing completed yet")
                                         : (search.isEmpty ? L("Il tuo primo post-it", "Your first note") : L("Nessun lavoro trovato", "No matching notes")))
                                        .font(PostItType.title())
                                    Label(L("Nuovo lavoro", "New note"), systemImage: "plus").font(.system(size: 12))
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
                                    .foregroundStyle(Color(red: 0.19, green: 0.22, blue: 0.19))
                                    .background(PaperSurface(color: .yellow))
                            }.buttonStyle(.plain)
                        }
                        ForEach(Array(rows(for: displayedNotes).enumerated()), id: \.element.id) { index, row in
                          switch row {
                          case .header(let category, let count):
                            CompletedHeader(category: category, count: count, language: language)
                                .zIndex(Double(index))
                          case .note(let note):
                            let value = current(note)
                            EditablePostIt(note: binding(for: note), value: value,
                                           staleDays: value.staleDays(threshold: staleAfterDays, now: now),
                                           language: language,
                                           isExpanded: expandedID == note.id,
                                           isHighlighted: highlightedID == note.id && expandedID != note.id,
                                           isNew: newIDs.contains(note.id),
                                           expand: {
                                               highlightedID = note.id
                                               toggleExpanded(note)
                                           },
                                           complete: { toggleCompleted(note, category: $0) },
                                           delete: { requestDeletion(note) },
                                           copyNote: { copyToPasteboard(current(note)) })
                                // Typing in one card must not rebuild every other sheet in the stack.
                                .equatable()
                                .background(BoardScrollMarker(id: note.id, isPriority: value.isPriority && value.completedAt == nil).allowsHitTesting(false).accessibilityHidden(true))
                                .id(note.id)
                                .zIndex(Double(index))
                          }
                        }
                        if !displayedNotes.isEmpty {
                            Color.clear.frame(height: 36).padding(.top, 18).allowsHitTesting(false)
                        }
                    }.padding(.horizontal, 10).padding(.vertical, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: min(notesHeight, max(100, maxHeight - 60 - (showsSearch ? 46 : 0))))


        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            // Resize in the same update as the content, not one scheduled task later.
            Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in
                resize(min(maxHeight, height))
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: .postItToggleSearch)) { _ in
            toggleSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .postItCopyNote)) { _ in
            if let id = expandedID ?? highlightedID, let target = displayedNotes.first(where: { $0.id == id }) {
                copyToPasteboard(current(target))
            } else if let first = displayedNotes.first {
                copyToPasteboard(current(first))
            } else {
                NSSound.beep()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .postItNavigateKey)) { notification in
            guard let keyCode = notification.userInfo?["keyCode"] as? UInt16 else { return }
            handleNavigationKey(keyCode, notes: displayedNotes)
        }
        .onReceive(store.$editRequest) { requested in
            guard let requested else { return }
            beginReading()
            PanelUndo.reset()
            completed = requested.completedAt != nil
            search = ""
            if !store.notes.contains(where: { $0.id == requested.id }) && !newNotes.contains(where: { $0.id == requested.id }) {
                newNotes.insert(requested, at: 0)
                drafts[requested.id] = requested
            }
            expandedID = requested.id
            highlightedID = requested.id
            store.editRequest = nil
        }
        .onReceive(store.externalUpdates) { note in
            guard drafts[note.id] != nil || expandedID == note.id else { return }
            if drafts[note.id] != nil { drafts[note.id] = note }
            // The open editors were rewritten from outside: their typing history no longer applies.
            if expandedID == note.id { PanelUndo.reset() }
        }
        .onChange(of: store.errorMessage) { _, message in
            if message != nil { NSApp.activate(ignoringOtherApps: true) }
        }
        .onChange(of: pendingDeletion?.id) { _, id in
            if id != nil { NSApp.activate(ignoringOtherApps: true) }
        }
        .alert(deletionTitle, isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button(L("Elimina", "Delete"), role: .destructive) {
                if let note = pendingDeletion { delete(note) }
                pendingDeletion = nil
            }
            Button(L("Annulla", "Cancel"), role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(L("Il post-it sparisce dalla lista e dal widget. Subito dopo puoi recuperarlo con ⌘Z.",
                   "The note disappears from the list and the widget. Right after, ⌘Z brings it back."))
        }
        .alert(L("Le note richiedono attenzione", "Your notes need attention"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func toggleSearch() {
        showsSearch.toggle()
        if showsSearch {
            DispatchQueue.main.async { searchFocused = true }
        } else {
            search = ""
            searchFocused = false
            beginReading()
        }
    }

    private func closeSearch() {
        showsSearch = false
        search = ""
        searchFocused = false
        beginReading()
    }

    private func handleEscapeOrHide() {
        if showsSearch {
            closeSearch()
        } else {
            hide()
        }
    }

    private func handleNavigationKey(_ keyCode: UInt16, notes: [WorkNote]) {
        guard !notes.isEmpty else { return }
        if keyCode == 36 || keyCode == 76 { // Return / Enter
            if let id = highlightedID ?? expandedID, let note = notes.first(where: { $0.id == id }) {
                toggleExpanded(note)
            } else if let first = notes.first {
                highlightedID = first.id
                toggleExpanded(first)
            }
            return
        }
        let currentID = highlightedID ?? expandedID
        let currentIndex = currentID.flatMap { id in notes.firstIndex { $0.id == id } }
        let nextIndex: Int
        if keyCode == 125 { // Down arrow
            nextIndex = currentIndex.map { min(notes.count - 1, $0 + 1) } ?? 0
        } else { // Up arrow (126)
            nextIndex = currentIndex.map { max(0, $0 - 1) } ?? (notes.count - 1)
        }
        highlightedID = notes[nextIndex].id
    }

    private func copyToPasteboard(_ note: WorkNote) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.formattedText(), forType: .string)
    }

    private func floatingButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 32, height: 32) }
            .buttonStyle(.plain).background(.regularMaterial, in: Circle()).help(label).accessibilityLabel(label)
    }

    private func current(_ note: WorkNote) -> WorkNote {
        drafts[note.id] ?? store.currentNote(id: note.id) ?? note
    }

    private func binding(for note: WorkNote) -> Binding<WorkNote> {
        Binding(get: { current(note) }, set: { updated in
            drafts[note.id] = updated
            if store.stageAutosave(updated) { newNotes.removeAll { $0.id == note.id } }
        })
    }

    private func showList(completed: Bool) {
        if self.completed != completed { PanelUndo.reset() }
        self.completed = completed
        search = ""
    }

    private func toggleExpanded(_ note: WorkNote) {
        // ⌘Z belongs to the open card: its editors are about to be replaced.
        PanelUndo.reset()
        if expandedID == note.id {
            if let draft = drafts[note.id], !store.stageAutosave(draft) { return }
            beginReading()
            discard(note)
            expandedID = nil
        } else {
            // Clear the previous editor before mounting the new card, never afterward.
            beginReading()
            expandedID = note.id
        }
    }

    private func move(_ source: UUID, relativeTo target: UUID, after: Bool) {
        let savedIDs = Set(store.notes.map(\.id))
        var ids = visibleNotes.filter { savedIDs.contains($0.id) }.map(\.id)
        guard source != target, let from = ids.firstIndex(of: source), ids.contains(target) else { return }
        ids.remove(at: from)
        guard let to = ids.firstIndex(of: target) else { return }
        ids.insert(source, at: to + (after ? 1 : 0))
        _ = store.reorder(ids)
    }

    private func addNote() {
        beginReading()
        PanelUndo.reset()
        var note = WorkNote()
        note.color = PaperColor(rawValue: defaultPaperColor) ?? .yellow
        completed = false
        search = ""
        drafts[note.id] = note
        newNotes.insert(note, at: 0)
        expandedID = note.id
        highlightedID = note.id
    }

    private func discard(_ note: WorkNote) {
        drafts.removeValue(forKey: note.id)
        newNotes.removeAll { $0.id == note.id }
    }

    // In progress: the plain stack. Completed: one section per category, newest first.
    private func rows(for notes: [WorkNote]) -> [BoardRow] {
        guard completed else { return notes.map(BoardRow.note) }
        return WorkNote.completedSections(notes).flatMap { section in
            [BoardRow.header(section.category, section.notes.count)] + section.notes.map(BoardRow.note)
        }
    }

    // `category` is chosen when completing; reopening passes nil and keeps the old one.
    private func toggleCompleted(_ original: WorkNote, category: NoteCategory?) {
        var note = current(original)
        let previous = note.completedAt
        note.completedAt = previous == nil ? Date() : nil
        if previous == nil, let category { note.category = category.rawValue }
        guard store.save(note) else { return }
        discard(original)
        expandedID = nil
        PanelUndo.reset()
        registerCompletionUndo(id: note.id, restore: previous, redo: note.completedAt,
                               name: previous == nil ? L("Completa", "Complete") : L("Riapri", "Reopen"))
    }

    private var deletionTitle: String {
        let title = pendingDeletion.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return title.isEmpty ? L("Eliminare questo post-it?", "Delete this note?")
                             : L("Eliminare «\(title)»?", "Delete “\(title)”?")
    }

    // A brand-new, still empty note goes at once; anything with content asks first.
    private func requestDeletion(_ original: WorkNote) {
        let note = current(original)
        let isEmpty = [note.title, note.progress, note.nextStep].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if isEmpty && !store.notes.contains(where: { $0.id == note.id }) {
            delete(note)
        } else {
            pendingDeletion = note
        }
    }

    private func delete(_ original: WorkNote) {
        let note = current(original)
        let saved = store.notes.contains { $0.id == note.id }
        if saved { guard store.delete(id: note.id) else { return } }
        discard(note)
        if expandedID == note.id { beginReading(); expandedID = nil }
        PanelUndo.reset()
        if saved { registerDeletionUndo(note) }
    }

    // ⌘Z puts a deleted note back; ⌘⇧Z deletes it again.
    private func registerDeletionUndo(_ note: WorkNote) {
        PanelUndo.register(L("Elimina", "Delete")) {
            guard store.restore(note) else { return }
            if note.completedAt != nil { completed = true }
            PanelUndo.register(L("Elimina", "Delete")) {
                guard store.delete(id: note.id) else { return }
                registerDeletionUndo(note)
            }
        }
    }

    // ⌘Z after Completa brings the card back to the list it came from, and vice versa.
    private func registerCompletionUndo(id: UUID, restore: Date?, redo: Date?, name: String) {
        PanelUndo.register(name) {
            guard var note = store.currentNote(id: id) else { return }
            note.completedAt = restore
            guard store.save(note) else { return }
            registerCompletionUndo(id: id, restore: redo, redo: restore, name: name)
        }
    }
}

private enum BoardRow: Identifiable {
    case header(NoteCategory?, Int)
    case note(WorkNote)

    var id: String {
        switch self {
        case .header(let category, _): return "section-\(category?.rawValue ?? "none")"
        case .note(let note): return note.id.uuidString
        }
    }
}

// A label between the stacks of the Completed list, readable over any wallpaper.
private struct CompletedHeader: View {
    let category: NoteCategory?
    let count: Int
    let language: AppLanguage

    var body: some View {
        HStack {
            Label("\(category?.sectionTitle ?? L("Senza categoria", "No category")) · \(count)",
                  systemImage: category?.symbol ?? "questionmark.folder")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            Spacer()
        }
        // The stack overlaps sheets by 18 pt; keep the label clear of both neighbours.
        .padding(.top, 30).padding(.bottom, 26)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct EditablePostIt: View, Equatable {
    @Binding var note: WorkNote
    // The binding's current value, compared so unchanged cards skip their body.
    let value: WorkNote
    let staleDays: Int?
    let language: AppLanguage
    let isExpanded: Bool
    let isHighlighted: Bool
    let isNew: Bool
    let expand: () -> Void
    let complete: (NoteCategory?) -> Void
    let delete: () -> Void
    let copyNote: () -> Void
    @State private var showsLink = false
    @State private var showsHistory = false
    @State private var showsCustomReminder = false
    @State private var customReminderDate = Date().addingTimeInterval(3600)
    @AppStorage(ReminderScheduler.deniedKey) private var notificationsDenied = false
    @State private var linkError: String?
    private let ink = Color(red: 0.19, green: 0.22, blue: 0.19)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value && lhs.staleDays == rhs.staleDays && lhs.language == rhs.language
            && lhs.isExpanded == rhs.isExpanded && lhs.isHighlighted == rhs.isHighlighted && lhs.isNew == rhs.isNew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    PaperTextEditor(text: $note.title, placeholder: L("Titolo del lavoro", "What are you working on?"),
                                    label: L("Titolo del lavoro", "Title"), fontSize: 21, bold: true, focusNewTitle: isNew)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12)).opacity(0.55).frame(width: 20, height: 28)
                        .overlay(PaperOpenArea(id: note.id, title: note.title, color: note.color,
                                               open: {}, opensOnClick: false, onDropLink: acceptDroppedLink))
                        .help(L("Trascina per riordinare", "Drag to reorder"))
                    Button(action: copyNote) { Image(systemName: "doc.on.doc").font(.system(size: 11)).padding(4) }
                        .buttonStyle(.plain).opacity(0.55)
                        .help(L("Copia come testo (⌘⇧C)", "Copy as text (⌘⇧C)"))
                        .accessibilityLabel(L("Copia come testo", "Copy as text"))
                    Button(action: delete) { Image(systemName: "trash").font(.system(size: 11)).padding(4) }
                        .buttonStyle(.plain).opacity(0.55)
                        .help(L("Elimina lavoro", "Delete note"))
                        .accessibilityLabel(L("Elimina lavoro", "Delete note"))
                    Button(action: expand) { Image(systemName: "chevron.up").font(.system(size: 11)).padding(4) }
                        .buttonStyle(.plain).accessibilityLabel(L("Chiudi il post-it", "Close note"))
                }
                writingField(L("Dove sono arrivato", "Where I left off"),
                             placeholder: L("Scrivi il punto da cui ripartire…", "Write the point to pick up from…"), text: $note.progress)
                if !note.steps.isEmpty { history }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(NextAction.allCases) { action in Button(action.label) { edit(L("Prossimo passo o attesa", "Next step or waiting")) { $0.action = action } } }
                    } label: {
                        Label(note.action.label, systemImage: note.action.symbol).font(.system(size: 10, weight: .semibold))
                    }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(L("Prossimo passo o attesa", "Next step or waiting"))
                    Spacer(minLength: 0)
                    Button(action: advanceStep) {
                        Label(L("Fatto", "Done"), systemImage: "arrow.turn.left.up").font(.system(size: 10, weight: .semibold))
                    }.buttonStyle(.plain)
                        .opacity(hasNextStep ? 0.75 : 0.3)
                        .disabled(!hasNextStep)
                        .help(L("Passo fatto (⌘↩): spostalo in “Dove sono arrivato”", "Step done (⌘↩): move it to “Where I left off”"))
                        .accessibilityLabel(L("Sposta il prossimo passo in Dove sono arrivato", "Move the next step to Where I left off"))
                }
                .onReceive(NotificationCenter.default.publisher(for: .postItAdvanceStep)) { _ in
                    if hasNextStep { advanceStep() } else { NSSound.beep() }
                }
                PaperTextEditor(text: $note.nextStep,
                                placeholder: note.action == .next ? L("Che cosa faccio dopo…", "What do I do next…")
                                                                 : L("Che cosa sto aspettando…", "What am I waiting for…"),
                                label: note.action.label)
                if note.action == .waiting { reminder }
                if showsLink || !(note.workLink ?? "").isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Cartella di lavoro o URL", "Work folder or URL")).font(.system(size: 10, weight: .semibold)).opacity(0.6)
                        PaperTextEditor(text: Binding(get: { note.workLink ?? "" }, set: { note.workLink = $0.isEmpty ? nil : $0 }),
                                        placeholder: L("https://… oppure scegli o trascina una cartella", "https://… or choose or drop a folder"),
                                        label: L("Cartella di lavoro o URL", "Work folder or URL"), fontSize: 16)
                        HStack(spacing: 14) {
                            Button(action: chooseFolder) { Label(L("Scegli cartella", "Choose folder"), systemImage: "folder") }
                            Button(action: openWorkLink) { Label(L("Apri", "Open"), systemImage: "arrow.up.right") }
                                .disabled(WorkLink.url(for: note.workLink) == nil)
                            Spacer()
                            Button {
                                edit(L("Rimuovi collegamento", "Remove link")) { $0.workLink = nil }
                                showsLink = false
                            } label: { Image(systemName: "xmark") }.accessibilityLabel(L("Rimuovi collegamento", "Remove link"))
                        }.font(.system(size: 10)).buttonStyle(.plain)
                        if !(note.workLink ?? "").isEmpty && WorkLink.url(for: note.workLink) == nil {
                            Text(L("Usa un URL https://… o un percorso di cartella.", "Use an https://… URL or a folder path.")).font(.system(size: 10)).opacity(0.7)
                        }
                    }
                } else {
                    Button { showsLink = true } label: {
                        Label(L("Collega cartella o URL", "Link a folder or URL"), systemImage: "link").font(.system(size: 10))
                    }.buttonStyle(.plain).opacity(0.65)
                }
                HStack(spacing: 6) {
                    ForEach(PaperColor.allCases) { color in
                        Button { edit(L("Colore", "Color")) { $0.color = color } } label: {
                            Circle().fill(color.paper).frame(width: 14, height: 14)
                                .overlay(Circle().stroke(note.color == color ? ink.opacity(0.7) : .clear, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel(color.label)
                            .accessibilityAddTraits(note.color == color ? .isSelected : [])
                    }
                    // Priority is for work still to do: a finished note offers its category instead.
                    if note.completedAt == nil {
                        Button(action: togglePriority) {
                            HStack(spacing: 5) {
                                PrioritySticker(size: 14).opacity(note.isPriority ? 1 : 0.35)
                                Text(L("Priorità", "Priority")).font(.system(size: 11, weight: .medium))
                            }.fixedSize()
                        }.buttonStyle(.plain).padding(.leading, 8)
                            .help(priorityActionTitle)
                            .accessibilityLabel(priorityActionTitle)
                            .accessibilityAddTraits(note.isPriority ? .isSelected : [])
                    }
                    Spacer()
                    if note.completedAt == nil {
                        // Completing asks what the work was, so the Completed list can group it.
                        Menu {
                            ForEach(NoteCategory.allCases) { category in
                                Button { complete(category) } label: { Label(category.label, systemImage: category.symbol) }
                            }
                        } label: {
                            Label(L("Completa", "Complete"), systemImage: "checkmark.circle").font(.system(size: 11, weight: .medium))
                        }.menuStyle(.borderlessButton).fixedSize()
                            .disabled(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help(L("Completa e scegli se è un’app, un sito web o altro", "Complete and file it as an app, a website or other"))
                    } else {
                        Menu {
                            ForEach(NoteCategory.allCases) { category in
                                Button { edit(L("Categoria", "Category")) { $0.category = category.rawValue } } label: {
                                    Label(category.label, systemImage: category.symbol)
                                }
                            }
                        } label: {
                            Label(note.noteCategory?.label ?? L("Categoria", "Category"),
                                  systemImage: note.noteCategory?.symbol ?? "folder").font(.system(size: 11, weight: .medium))
                        }.menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel(L("Categoria", "Category"))
                        Button { complete(nil) } label: {
                            Label(L("Riapri", "Reopen"), systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .medium))
                                .fixedSize()
                        }.buttonStyle(.plain).padding(.leading, 8)
                    }
                }.padding(.top, 6)
            } else {
                HStack(alignment: .center, spacing: 8) {
                        Text(note.title.isEmpty ? L("Nuovo lavoro", "New note") : note.title)
                            .font(PostItType.title()).lineLimit(1).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if WorkLink.url(for: note.workLink) != nil {
                            Image(systemName: WorkLink.isFolder(note.workLink) ? "folder" : "link")
                                .font(.system(size: 9)).opacity(0.5)
                        }
                        if note.action == .waiting, note.completedAt == nil, let date = note.reminderAt {
                            Image(systemName: date > Date() ? "bell.fill" : "bell.badge.fill")
                                .font(.system(size: 9)).opacity(date > Date() ? 0.5 : 0.85)
                        }
                        if let completedAt = note.completedAt {
                            Text(completedAt.localized(.dateTime.day().month(.abbreviated)))
                                .font(.system(size: 10, weight: .semibold).monospacedDigit()).opacity(0.5)
                                .fixedSize()
                        }
                        if let staleDays {
                            Label("\(staleDays) \(L("g", "d"))", systemImage: "clock")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit()).opacity(0.6)
                                .fixedSize()
                        }
                        Image(systemName: "chevron.down").font(.system(size: 10)).opacity(0.55)
                    }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .padding(.horizontal, 24).padding(.bottom, 18)
                        .accessibilityHidden(true)
                        .overlay(PaperOpenArea(id: note.id, title: collapsedLabel, color: note.color, open: expand,
                                               contextItems: contextItems, onDropLink: acceptDroppedLink))
            }
        }
        .padding(.horizontal, isExpanded ? 24 : 0)
        .padding(.top, isExpanded ? 24 : 0)
        .padding(.bottom, isExpanded ? 42 : 0)
        .foregroundStyle(ink)
        // Shadow only the paper image: shadowing the whole card forces an offscreen pass
        // over every text view and control on each redraw.
        .background(PaperSurface(color: note.color).shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: -2))
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 4).strokeBorder(ink.opacity(0.35), lineWidth: 1.5).allowsHitTesting(false)
            }
        }
        // Stuck on the top-left corner, half over the edge, clear of the title.
        .overlay(alignment: .topLeading) {
            if note.isPriority && note.completedAt == nil { PrioritySticker().offset(x: -6, y: -6).allowsHitTesting(false) }
        }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: nil) { providers in
            handleSwiftUIDrop(providers)
        }
        .onChange(of: linkError) { _, message in
            if message != nil { NSApp.activate(ignoringOtherApps: true) }
        }
        .alert(L("Collegamento non disponibile", "Link unavailable"), isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } })) {
            Button("OK") { linkError = nil }
        } message: { Text(linkError ?? "") }
    }

    private var hasNextStep: Bool { !note.trimmedNextStep.isEmpty }

    private var collapsedLabel: String {
        var title = note.title.isEmpty ? L("Nuovo lavoro", "New note") : note.title
        if note.isPriority { title = L("Priorità: ", "Priority: ") + title }
        guard let staleDays else { return title }
        return L("\(title), fermo da \(staleDays) giorni", "\(title), untouched for \(staleDays) days")
    }

    private var contextItems: [PaperOpenArea.ContextItem] {
        var items: [PaperOpenArea.ContextItem] = []
        if note.completedAt == nil {
            if hasNextStep {
                items.append(.init(title: L("Passo fatto", "Mark step done"), action: advanceStep))
            }
            items.append(.init(title: priorityActionTitle, action: togglePriority))
        }
        if WorkLink.url(for: note.workLink) != nil {
            let openTitle = WorkLink.isFolder(note.workLink)
                ? L("Apri cartella collegata", "Open linked folder")
                : L("Apri URL collegato", "Open linked URL")
            items.append(.init(title: openTitle, action: openWorkLink))
        }
        items.append(.init(title: L("Copia come testo", "Copy as text"), action: copyNote))
        items.append(.separator())
        items.append(.init(title: L("Elimina lavoro…", "Delete note…"), action: delete))
        return items
    }

    private var priorityActionTitle: String {
        note.isPriority ? L("Togli l’adesivo di priorità", "Remove priority sticker")
                        : L("Metti l’adesivo di priorità", "Add priority sticker")
    }

    private func togglePriority() {
        edit(L("Priorità", "Priority")) { $0.priority = $0.isPriority ? nil : true }
    }

    private func acceptDroppedLink(_ link: String) {
        edit(L("Collega cartella o URL", "Link folder or URL")) { $0.workLink = link }
        if isExpanded { showsLink = true }
    }

    private func handleSwiftUIDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let valid = WorkLink.url(for: url.path) else { return }
                Task { @MainActor in acceptDroppedLink(valid.path) }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier("public.url") {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let valid = WorkLink.url(for: url.absoluteString) else { return }
                Task { @MainActor in acceptDroppedLink(valid.isFileURL ? valid.path : valid.absoluteString) }
            }
            return true
        }
        return false
    }

    // "In attesa" can ring later: macOS shows a notification that opens this post-it.
    private var reminder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(ReminderPreset.allCases) { preset in
                    Button(preset.label) {
                        showsCustomReminder = false
                        edit(L("Promemoria", "Reminder")) { $0.reminderAt = preset.date() }
                    }
                }
                Divider()
                Button(L("Data e ora…", "Custom date & time…")) {
                    customReminderDate = note.reminderAt ?? ReminderPreset.tomorrow.date()
                    showsCustomReminder = true
                }
                if note.reminderAt != nil {
                    Divider()
                    Button(L("Rimuovi promemoria", "Remove reminder")) {
                        showsCustomReminder = false
                        edit(L("Rimuovi promemoria", "Remove reminder")) { $0.reminderAt = nil }
                    }
                }
            } label: {
                Label(reminderText, systemImage: note.reminderAt == nil ? "bell" : "bell.fill")
                    .font(.system(size: 10, weight: .semibold))
            }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(reminderText)
            if showsCustomReminder {
                HStack(spacing: 8) {
                    DatePicker("", selection: $customReminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .controlSize(.small)
                    Button(L("Imposta", "Set")) {
                        showsCustomReminder = false
                        edit(L("Promemoria", "Reminder")) { $0.reminderAt = customReminderDate }
                    }.font(.system(size: 10, weight: .semibold)).buttonStyle(.plain)
                    Button {
                        showsCustomReminder = false
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }.buttonStyle(.plain).opacity(0.6)
                }
            }
            if notificationsDenied, note.reminderAt != nil {
                Text(L("Attiva le notifiche di What’s Next? in Impostazioni di Sistema › Notifiche.",
                       "Turn on notifications for What’s Next? in System Settings › Notifications."))
                    .font(.system(size: 10)).opacity(0.7)
            }
        }
    }

    private var reminderText: String {
        guard let date = note.reminderAt else { return L("Ricordamelo", "Remind me") }
        let when = date.localized(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        return date > Date() ? L("Promemoria: \(when)", "Reminder: \(when)") : L("Promemoria passato: \(when)", "Reminder passed: \(when)")
    }

    // The step just finished becomes the new starting point; the old one joins the history.
    private func advanceStep() {
        edit(L("Fatto", "Done")) { $0.advanceStep() }
    }

    // Earlier points, newest first. Folded by default so the card stays short.
    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showsHistory.toggle() } label: {
                Label(L("Percorso", "Path") + " · \(note.steps.count)", systemImage: showsHistory ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }.buttonStyle(.plain).opacity(0.6)
                .accessibilityLabel(showsHistory ? L("Nascondi il percorso", "Hide path") : L("Mostra il percorso", "Show path"))
            if showsHistory {
                ForEach(note.steps.reversed()) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date.localized(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 10).monospacedDigit()).opacity(0.55)
                            .frame(width: 44, alignment: .leading)
                        Text(entry.text).font(PostItType.body(15)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { edit(L("Rimuovi dal percorso", "Remove from path")) { $0.history = $0.steps.filter { $0.id != entry.id } } } label: {
                            Image(systemName: "xmark").font(.system(size: 9))
                        }.buttonStyle(.plain).opacity(0.4).accessibilityLabel(L("Rimuovi dal percorso", "Remove from path"))
                    }
                }
            }
        }
    }

    // Apply a card action as one change and make it reversible with ⌘Z / ⌘⇧Z.
    private func edit(_ name: String, _ change: (inout WorkNote) -> Void) {
        let before = note
        var after = before
        change(&after)
        guard after != before else { return }
        note = after
        let binding = $note
        PanelUndo.registerNote(name, restore: before, redo: after) { binding.wrappedValue = $0 }
    }

    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.title = L("Scegli la cartella di lavoro", "Choose the work folder")
        picker.prompt = L("Collega cartella", "Link folder")
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        if let current = WorkLink.url(for: note.workLink), current.isFileURL { picker.directoryURL = current }
        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK, let url = picker.url { edit(L("Scegli cartella", "Choose folder")) { $0.workLink = url.path } }
    }

    private func openWorkLink() {
        guard let url = WorkLink.url(for: note.workLink) else { return }
        if !NSWorkspace.shared.open(url) {
            linkError = L("Non riesco ad aprire il collegamento. Controlla che la cartella esista o che l’URL sia corretto.",
                          "The link can’t be opened. Check that the folder exists or that the URL is correct.")
        }
    }

    private func writingField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10, weight: .semibold)).opacity(0.6)
            PaperTextEditor(text: text, placeholder: placeholder, label: label)

        }
    }
}
