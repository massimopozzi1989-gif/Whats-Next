import Foundation

// WidgetKit has a fixed canvas. Fit readable titles, then page rather than discard notes.
struct WidgetPageLayout {
    let capacity: Int
    let pageCount: Int
    let page: Int
    let range: Range<Int>
    let footerHeight: CGFloat
    let paperHeight: CGFloat

    init(count: Int, height: CGFloat, single: Bool, requestedPage: Int) {
        let available = max(1, height)
        let initialCapacity = single ? 1 : max(1, Int(max(0, available - 18) / 36))
        footerHeight = count > initialCapacity ? 28 : 0
        capacity = single ? 1 : max(1, Int(max(0, available - footerHeight - 18) / 36))
        pageCount = max(1, (count + capacity - 1) / capacity)
        page = min(max(0, requestedPage), pageCount - 1)
        let start = min(count, page * capacity)
        let end = min(count, start + capacity)
        range = start..<end
        let rows = max(1, end - start)
        paperHeight = max(1, (available - footerHeight + 18 * CGFloat(rows - 1)) / CGFloat(rows))
    }
}
