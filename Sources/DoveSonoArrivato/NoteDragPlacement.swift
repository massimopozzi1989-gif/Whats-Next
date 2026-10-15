import Foundation

struct NoteDragRow {
    let id: UUID
    let frame: CGRect
    var isPriority: Bool = false

    init(id: UUID, frame: CGRect, isPriority: Bool = false) {
        self.id = id
        self.frame = frame
        self.isPriority = isPriority
    }
}

struct NoteDragPlacement: Equatable {
    let target: UUID
    let after: Bool
    let indicatorY: CGFloat

    static func resolve(y: CGFloat, rows: [NoteDragRow], sourceID: UUID? = nil) -> NoteDragPlacement? {
        let sorted = rows.sorted { $0.frame.minY < $1.frame.minY }
        // Priority notes stay at the top of the stack; constrain drop targets to the same group
        // so the blue insertion line always matches where the card actually lands.
        let filtered: [NoteDragRow]
        if let sourceID, let sourceRow = sorted.first(where: { $0.id == sourceID }) {
            let group = sorted.filter { $0.isPriority == sourceRow.isPriority }
            filtered = group.isEmpty ? sorted : group
        } else {
            filtered = sorted
        }
        for index in filtered.indices {
            // Overlapping paper hides the previous sheet's lower edge. Use the visible
            // strip, so the upper/lower halves agree with what the person actually sees.
            let row = filtered[index]
            let nextInAll = sorted.first { $0.frame.minY > row.frame.minY }
            let end = min(row.frame.maxY, nextInAll?.frame.minY ?? row.frame.maxY)
            if y < (row.frame.minY + end) / 2 {
                return NoteDragPlacement(target: row.id, after: false, indicatorY: row.frame.minY)
            }
        }
        guard let last = filtered.last else { return nil }
        return NoteDragPlacement(target: last.id, after: true, indicatorY: last.frame.maxY)
    }

    static func scrollDelta(y: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let edge = min(48, viewportHeight / 3)
        guard edge > 0 else { return 0 }
        if y < edge {
            let strength = min(1, max(0, (edge - y) / edge))
            return -(2 + 14 * strength * strength)
        }
        if y > viewportHeight - edge {
            let strength = min(1, max(0, (y - viewportHeight + edge) / edge))
            return 2 + 14 * strength * strength
        }
        return 0
    }
}
