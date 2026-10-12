import Foundation

enum WidgetSnapshot {
    static let kind = "DoveSonoArrivatoPostIt"
    static let group = "8ZN67F8SW8.it.massimopozzi.dovesonoarrivato"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("widget-notes.json")
    }

    static func read() -> [WorkNote] {
        guard let url, let data = try? Data(contentsOf: url),
              let notes = try? JSONDecoder().decode([WorkNote].self, from: data) else { return [] }
        return WorkNote.ordered(notes)
    }

    static func write(_ notes: [WorkNote]) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(notes).write(to: url, options: .atomic)
    }

    static let openPanel = URL(string: "dovesonoarrivato://open")!

    static func link(_ note: WorkNote) -> URL {
        URL(string: "dovesonoarrivato://note/\(note.id.uuidString)")!
    }
}
