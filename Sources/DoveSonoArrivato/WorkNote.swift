import Foundation

enum NextAction: String, Codable, CaseIterable, Identifiable {
    case next = "Prossimo passo"
    case waiting = "In attesa"
    var id: String { rawValue }
    var symbol: String { self == .next ? "arrow.right" : "hourglass" }
    // rawValue is stored in notes.json and must never change; show this instead.
    var label: String { self == .next ? L("Prossimo passo", "Next step") : L("In attesa", "Waiting for") }
}

enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case yellow, peach, mint, blue, lilac
    var id: String { rawValue }
    var label: String {
        switch self {
        case .yellow: return L("Giallo", "Yellow")
        case .peach: return L("Pesca", "Peach")
        case .mint: return L("Verde", "Mint")
        case .blue: return L("Azzurro", "Blue")
        case .lilac: return L("Lilla", "Lilac")
        }
    }
}

// What a finished note was: chosen when completing it, used to group the Completed list.
enum NoteCategory: String, CaseIterable, Identifiable {
    case app, website, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .app: return L("App", "App")
        case .website: return L("Sito web", "Website")
        case .other: return L("Altro", "Other")
        }
    }
    var sectionTitle: String {
        switch self {
        case .app: return L("App", "Apps")
        case .website: return L("Siti web", "Websites")
        case .other: return L("Altro", "Other")
        }
    }
    var symbol: String {
        switch self {
        case .app: return "square.grid.2x2"
        case .website: return "globe"
        case .other: return "tray"
        }
    }
}

// A point the work has moved past, archived when "Fatto" advances the note.
struct StepEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var date: Date
}

struct WorkNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var progress = ""
    var action: NextAction = .next
    var nextStep = ""
    var conclusion = ""
    var workLink: String?
    var color: PaperColor = .yellow
    var updatedAt = Date()
    var completedAt: Date?
    var sortPosition: Int?
    // Optional so notes saved by earlier versions still decode.
    var history: [StepEntry]?
    // When to be reminded about an "In attesa" note. Optional for older files.
    var reminderAt: Date?
    // The priority sticker. Optional so files from earlier versions still decode.
    var priority: Bool?

    var isPriority: Bool { priority == true }
    // Stored as text so an unknown value from a newer version never breaks decoding.
    var category: String?

    var noteCategory: NoteCategory? { category.flatMap(NoteCategory.init(rawValue:)) }

    // The Completed list: Apps, Websites, Other, then notes completed before categories
    // existed. Newest first inside each section.
    static func completedSections(_ notes: [WorkNote]) -> [(category: NoteCategory?, notes: [WorkNote])] {
        let order: [NoteCategory?] = NoteCategory.allCases.map { Optional($0) } + [nil]
        return order.compactMap { category in
            let members = notes.filter { $0.noteCategory == category }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return members.isEmpty ? nil : (category, members)
        }
    }

    var steps: [StepEntry] { history ?? [] }

    var trimmedNextStep: String { nextStep.trimmingCharacters(in: .whitespacesAndNewlines) }

    // "Fatto": the next step becomes where I am; the previous point moves to the history.
    @discardableResult
    mutating func advanceStep(at date: Date = Date()) -> Bool {
        let step = trimmedNextStep
        guard !step.isEmpty else { return false }
        let previous = progress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !previous.isEmpty { history = steps + [StepEntry(text: previous, date: date)] }
        progress = step
        nextStep = ""
        action = .next
        reminderAt = nil
        return true
    }

    // Whole days since the last edit; reordering or opening a card does not count.
    func idleDays(now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: updatedAt),
                                       to: calendar.startOfDay(for: now)).day ?? 0)
    }

    // An open note untouched for at least `threshold` days. Waiting with a future
    // reminder is intentional, not forgotten.
    func staleDays(threshold: Int, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard threshold > 0, completedAt == nil else { return nil }
        if action == .waiting, let reminderAt, reminderAt > now { return nil }
        let days = idleDays(now: now, calendar: calendar)
        return days >= threshold ? days : nil
    }

    // Notes with the priority sticker come first; each group keeps its manual order.
    static func priorityFirst(_ notes: [WorkNote]) -> [WorkNote] {
        notes.filter(\.isPriority) + notes.filter { !$0.isPriority }
    }

    static func ordered(_ notes: [WorkNote]) -> [WorkNote] {
        notes.sorted {
            let left = $0.sortPosition ?? Int.max
            let right = $1.sortPosition ?? Int.max
            if left != right { return left < right }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
