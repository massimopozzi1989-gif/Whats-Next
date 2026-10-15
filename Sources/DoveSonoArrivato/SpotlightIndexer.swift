import Foundation
import CoreSpotlight

enum SpotlightIndexer {
    static let domainIdentifier = "it.massimopozzi.dovesonoarrivato.notes"
    static let prefix = "dovesonoarrivato://note/"

    static func searchableItem(for note: WorkNote) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        let cleanTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        attributes.title = cleanTitle.isEmpty ? L("Nuovo lavoro", "New note") : cleanTitle
        var parts: [String] = []
        let cleanProgress = note.progress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanProgress.isEmpty { parts.append(cleanProgress) }
        let cleanNext = note.trimmedNextStep
        if !cleanNext.isEmpty { parts.append("\(note.action.label): \(cleanNext)") }
        attributes.contentDescription = parts.joined(separator: " — ")
        attributes.contentModificationDate = note.updatedAt
        var keywords = [note.color.label]
        if note.isPriority { keywords.append(L("Priorità", "Priority")) }
        if let cat = note.noteCategory { keywords.append(cat.label) }
        attributes.keywords = keywords
        return CSSearchableItem(
            uniqueIdentifier: WidgetSnapshot.link(note).absoluteString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }

    static func noteID(from userActivity: NSUserActivity) -> UUID? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let url = URL(string: identifier),
              case .note(let id) = PanelRoute(url: url) else {
            return nil
        }
        return id
    }

    static func reindex(_ notes: [WorkNote]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items = notes.map(searchableItem(for:))
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items, completionHandler: nil)
        }
    }
}
