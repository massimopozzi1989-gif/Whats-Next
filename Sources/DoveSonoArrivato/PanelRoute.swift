import Foundation

enum PanelRoute: Equatable {
    case new
    case show
    case note(UUID)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "dovesonoarrivato" else { return nil }
        switch url.host {
        case "new": self = .new
        case "open": self = .show
        case "note":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .note(id)
        default: return nil
        }
    }
}
