import Foundation

struct NoteDragRow {
    let id: UUID
    let frame: CGRect
}

struct NoteDragPlacement: Equatable {
    let target: UUID
    let after: Bool
    let indicatorY: CGFloat

    static func resolve(y: CGFloat, rows: [NoteDragRow]) -> NoteDragPlacement? {
        let rows = rows.sorted { $0.frame.minY < $1.frame.minY }
        for index in rows.indices {
            // Overlapping paper hides the previous sheet's lower edge. Use the visible
            // strip, so the upper/lower halves agree with what the person actually sees.
            let end = index + 1 < rows.count ? rows[index + 1].frame.minY : rows[index].frame.maxY
            if y < (rows[index].frame.minY + end) / 2 {
                return NoteDragPlacement(target: rows[index].id, after: false, indicatorY: rows[index].frame.minY)
            }
        }
        guard let last = rows.last else { return nil }
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
