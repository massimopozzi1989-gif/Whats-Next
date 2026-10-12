import AppIntents
import SwiftUI
import WidgetKit

struct NoteEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lavoro")
    static var defaultQuery = NoteQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct NoteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [NoteEntity] {
        WidgetSnapshot.read().filter { identifiers.contains($0.id.uuidString) }
            .map { NoteEntity(id: $0.id.uuidString, title: $0.title) }
    }
    func suggestedEntities() async throws -> [NoteEntity] {
        WidgetSnapshot.read().filter { $0.completedAt == nil }
            .map { NoteEntity(id: $0.id.uuidString, title: $0.title) }
    }
}

struct PostItConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Il tuo post-it"
    static var description = IntentDescription("Scegli un lavoro oppure mostra tutti i post-it in ordine.")
    @Parameter(title: "Lavoro") var note: NoteEntity?
    @Parameter(title: "Mostra i completati", default: false) var completed: Bool
}

struct ChangePostItPage: AppIntent {
    static var title: LocalizedStringResource = "Sfoglia i post-it"
    static var openAppWhenRun = false
    @Parameter(title: "Pagina") var page: Int
    @Parameter(title: "Completati") var completed: Bool
    @Parameter(title: "Formato") var format: String

    init() {}
    init(page: Int, completed: Bool, format: String) {
        self.page = page
        self.completed = completed
        self.format = format
    }
    static func key(completed: Bool, format: String) -> String {
        "postit-page-\(completed ? "completed" : "active")-\(format)"
    }
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WidgetSnapshot.group)?.set(max(0, page),
            forKey: Self.key(completed: completed, format: format))
        return .result()
    }
}

// "Fatto" from the widget: advance the snapshot at once, queue the change for the app.
struct AdvancePostItStep: AppIntent {
    static var title: LocalizedStringResource = "Passo fatto"
    static var openAppWhenRun = false
    static var isDiscoverable = false
    @Parameter(title: "Lavoro") var noteID: String

    init() {}
    init(note: WorkNote) { noteID = note.id.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: noteID) else { return .result() }
        var notes = WidgetSnapshot.read()
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return .result() }
        let step = notes[index].trimmedNextStep
        let now = Date()
        guard notes[index].advanceStep(at: now) else { return .result() }
        try WidgetActions.enqueue(WidgetAdvanceAction(noteID: id, step: step, date: now))
        try WidgetSnapshot.write(notes)
        WidgetActions.notifyApp()
        return .result()
    }
}

struct PostItEntry: TimelineEntry {
    let date: Date
    let notes: [WorkNote]
    let selected: Bool
    let completed: Bool
    var pages: [String: Int] = [:]
    // The sample sheet WidgetKit shows while loading: it is not a real note.
    var isPlaceholder = false
}

// The widget process follows the language chosen in the app, read from the App Group.
private func adoptAppLanguage() {
    AppLanguage.forced = AppLanguage.readShared()
}

struct PostItProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PostItEntry {
        adoptAppLanguage()
        var note = WorkNote()
        note.title = L("Il mio lavoro", "My project")
        note.progress = L("Il punto da cui ripartire.", "The point to pick up from.")
        note.nextStep = L("Il prossimo piccolo passo.", "The next small step.")
        return PostItEntry(date: .now, notes: [note], selected: false, completed: false, isPlaceholder: true)
    }
    func snapshot(for configuration: PostItConfiguration, in context: Context) async -> PostItEntry {
        entry(configuration)
    }
    func timeline(for configuration: PostItConfiguration, in context: Context) async -> Timeline<PostItEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(900)))
    }
    private func entry(_ configuration: PostItConfiguration) -> PostItEntry {
        adoptAppLanguage()
        let notes = WidgetSnapshot.read().filter {
            if let selected = configuration.note { return $0.id.uuidString == selected.id }
            return ($0.completedAt != nil) == configuration.completed
        }
        let defaults = UserDefaults(suiteName: WidgetSnapshot.group)
        let pages = Dictionary(uniqueKeysWithValues: ["small", "medium", "large"].map { format in
            (format, defaults?.integer(forKey: ChangePostItPage.key(completed: configuration.completed, format: format)) ?? 0)
        })
        return PostItEntry(date: .now, notes: notes, selected: configuration.note != nil,
                           completed: configuration.completed, pages: pages)
    }
}

struct PostItWidgetView: View {
    let entry: PostItEntry
    @Environment(\.widgetFamily) private var family
    private var format: String {
        switch family {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        default: return "large"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = WidgetPageLayout(count: entry.notes.count, height: geometry.size.height,
                single: entry.selected || family == .systemSmall, requestedPage: entry.pages[format] ?? 0)
            let displayed = Array(entry.notes[layout.range])
            let single = entry.selected || family == .systemSmall
            VStack(spacing: 0) {
                VStack(spacing: -18) {
                    if displayed.isEmpty {
                        Link(destination: URL(string: "dovesonoarrivato://new")!) {
                            Label(entry.completed ? L("Nessun lavoro completato", "Nothing completed yet") : L("Un nuovo post-it", "A new note"), systemImage: "plus")
                                .font(PostItType.title(20))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20).background(PaperSurface(color: .yellow))
                        }.buttonStyle(.plain)
                    } else {
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, note in
                            let canAdvance = !entry.isPlaceholder && !note.trimmedNextStep.isEmpty
                            ZStack(alignment: .topTrailing) {
                                Link(destination: entry.isPlaceholder ? WidgetSnapshot.openPanel : WidgetSnapshot.link(note)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(note.title.isEmpty ? L("Nuovo lavoro", "New note") : note.title)
                                            .font(PostItType.title(displayed.count > 5 ? 18 : 20))
                                            .lineLimit(1).minimumScaleFactor(0.7)
                                        if single { details(note) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, note.isPriority ? 30 : 18).padding(.trailing, canAdvance ? 40 : 18).padding(.top, 9)
                                    .frame(height: layout.paperHeight, alignment: .top)
                                    .background(PaperSurface(color: note.color))
                                    .overlay(alignment: .topLeading) {
                                        if note.isPriority { PrioritySticker(size: 18).offset(x: 6, y: 5) }
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel((note.isPriority ? L("Priorità: ", "Priority: ") : "")
                                        + (note.title.isEmpty ? L("Nuovo lavoro", "New note") : note.title))
                                if canAdvance {
                                    Button(intent: AdvancePostItStep(note: note)) {
                                        Image(systemName: "arrow.turn.left.up")
                                            .font(.system(size: 11, weight: .semibold)).frame(width: 30, height: 30)
                                    }.buttonStyle(.plain).padding(.top, 5).padding(.trailing, 6)
                                        .accessibilityLabel(L("Passo fatto: ", "Step done: ") + note.trimmedNextStep)
                                }
                            }
                            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: -2)
                            .zIndex(Double(index))
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if layout.pageCount > 1 {
                    HStack {
                        Button(intent: ChangePostItPage(page: layout.page - 1, completed: entry.completed, format: format)) {
                            Image(systemName: "chevron.left").frame(width: 36, height: 28)
                        }.disabled(layout.page == 0).accessibilityLabel(L("Post-it precedenti", "Previous notes"))
                        Spacer()
                        Text("\(layout.range.lowerBound + 1)–\(layout.range.upperBound) \(L("di", "of")) \(entry.notes.count)")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Spacer()
                        Button(intent: ChangePostItPage(page: layout.page + 1, completed: entry.completed, format: format)) {
                            Image(systemName: "chevron.right").frame(width: 36, height: 28)
                        }.disabled(layout.page == layout.pageCount - 1).accessibilityLabel(L("Post-it successivi", "Next notes"))
                    }.buttonStyle(.plain).padding(.horizontal, 8).frame(height: layout.footerHeight)
                }
            }.foregroundStyle(Color(red: 0.19, green: 0.22, blue: 0.19))
                .widgetURL(family == .systemSmall ?
                    (entry.isPlaceholder ? WidgetSnapshot.openPanel
                        : displayed.first.map(WidgetSnapshot.link) ?? URL(string: "dovesonoarrivato://new")!) : nil)
        }
        .containerBackground(for: .widget) {
            (entry.notes.last?.color ?? .yellow).paper
        }
    }
}

extension PostItWidgetView {
    // One note on the canvas: show where I am and what comes next, so "Fatto" is informed.
    @ViewBuilder
    func details(_ note: WorkNote) -> some View {
        let progress = note.progress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !progress.isEmpty {
            Text(progress).font(PostItType.body(family == .systemSmall ? 13 : 15)).lineLimit(family == .systemSmall ? 2 : 4)
        }
        if !note.trimmedNextStep.isEmpty {
            Label(note.trimmedNextStep, systemImage: note.action.symbol)
                .font(.system(size: 11, weight: .medium)).lineLimit(2).opacity(0.75)
        }
    }
}

@main
struct PostItWidget: Widget {
    init() { adoptAppLanguage() }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSnapshot.kind, intent: PostItConfiguration.self, provider: PostItProvider()) { entry in
            PostItWidgetView(entry: entry)
        }
        .configurationDisplayName("What’s Next?")
        .description(L("I tuoi lavori su veri post-it. Tocca la carta per scrivere nell’app.",
                       "Your work on real paper notes. Tap a note to write in the app."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
