import Foundation
import AppKit

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

    static func isFolder(_ text: String?) -> Bool {
        guard let url = url(for: text) else { return false }
        return url.isFileURL
    }

    // Extract a valid folder path or web URL dragged from Finder or a browser.
    static func droppedLink(from pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for candidate in urls {
                if candidate.isFileURL, candidate.path.hasPrefix("/") {
                    return candidate.path
                }
                if let valid = url(for: candidate.absoluteString) {
                    return valid.absoluteString
                }
            }
        }
        if let raw = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .fileURL) ?? pasteboard.string(forType: .string),
           let valid = url(for: raw) {
            return valid.isFileURL ? valid.path : valid.absoluteString
        }
        return nil
    }
}
