import Foundation

enum WorkLink {
    static func url(for text: String?) -> URL? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw, isDirectory: true) }
        if raw.hasPrefix("~/") {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        let value = raw.lowercased().hasPrefix("www.") ? "https://\(raw)" : raw
        guard let url = URL(string: value) else { return nil }
        if url.isFileURL && url.path.hasPrefix("/") { return url }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
