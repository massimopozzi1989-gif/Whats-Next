import Foundation

// Two languages, switchable at runtime from Settings without restarting.
// Strings live next to their use as L("italiano", "English").
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case italian = "it"
    case english = "en"

    var id: String { rawValue }
    static let key = "appLanguage"

    // The widget runs in its own process: it pins the language the app published.
    static var forced: AppLanguage?

    static var preference: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    static var current: AppLanguage {
        forced ?? resolve(preference, preferred: Locale.preferredLanguages)
    }

    static func resolve(_ preference: AppLanguage, preferred: [String]) -> AppLanguage {
        if preference != .system { return preference }
        return preferred.first?.lowercased().hasPrefix("it") == true ? .italian : .english
    }

    var locale: Locale {
        Locale(identifier: self == .italian ? "it_IT" : "en_US")
    }

    // Shared file the widget reads; the app writes the resolved language.
    static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appendingPathComponent("language")
    }

    static func readShared() -> AppLanguage? {
        guard let url = sharedURL, let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return AppLanguage(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func writeShared(_ language: AppLanguage) throws {
        guard let url = sharedURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try language.rawValue.write(to: url, atomically: true, encoding: .utf8)
    }
}

func L(_ italian: String, _ english: String) -> String {
    AppLanguage.current == .english ? english : italian
}

extension Date {
    func localized(_ format: Date.FormatStyle) -> String {
        formatted(format.locale(AppLanguage.current.locale))
    }
}
