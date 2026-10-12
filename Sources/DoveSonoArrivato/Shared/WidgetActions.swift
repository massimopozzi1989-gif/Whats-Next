import Foundation

// "Fatto" pressed in the widget. The step text makes applying it idempotent:
// the app advances the note only if that is still its next step.
struct WidgetAdvanceAction: Codable, Equatable {
    var noteID: UUID
    var step: String
    var date: Date
}

// The widget cannot write the app's notes, so it leaves one file per action in the
// App Group and wakes the app; the app applies and deletes them (also at launch).
enum WidgetActions {
    static let notification = "it.massimopozzi.dovesonoarrivato.widget-action"

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appendingPathComponent("widget-actions", isDirectory: true)
    }

    static func enqueue(_ action: WidgetAdvanceAction, in directory: URL? = directory) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        try JSONEncoder().encode(action).write(to: file, options: .atomic)
    }

    static func pending(in directory: URL? = directory) -> [(file: URL, action: WidgetAdvanceAction)] {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file) else { return nil }
            guard let action = try? JSONDecoder().decode(WidgetAdvanceAction.self, from: data) else {
                // Files are written atomically, so an unreadable one can never become valid:
                // drop it instead of rereading it on every launch.
                remove(file)
                return nil
            }
            return (file, action)
        }.sorted { $0.action.date < $1.action.date }
    }

    static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    static func notifyApp() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notification as CFString), nil, nil, true)
    }
}
