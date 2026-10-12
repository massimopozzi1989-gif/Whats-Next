import XCTest
@testable import DoveSonoArrivato

final class WidgetPageLayoutTests: XCTestCase {
    func testSevenNotesFitTogetherInLargeWidget() {
        let layout = WidgetPageLayout(count: 7, height: 340, single: false, requestedPage: 0)
        XCTAssertEqual(layout.range, 0..<7)
        XCTAssertEqual(layout.pageCount, 1)
        XCTAssertEqual(layout.footerHeight, 0)
        XCTAssertEqual(layout.paperHeight * 7 - 18 * 6, 340, accuracy: 0.001)
    }

    func testEveryNoteIsReachableInSmallerFormatsWithoutClipping() {
        for height: CGFloat in [150, 170, 300, 340] {
            for count in [0, 1, 7, 12, 100] {
                let first = WidgetPageLayout(count: count, height: height, single: false, requestedPage: 0)
                var seen: [Int] = []
                for page in 0..<first.pageCount {
                    let layout = WidgetPageLayout(count: count, height: height, single: false, requestedPage: page)
                    seen.append(contentsOf: layout.range)
                    if !layout.range.isEmpty {
                        let rows = CGFloat(layout.range.count)
                        XCTAssertLessThanOrEqual(layout.paperHeight * rows - 18 * (rows - 1) + layout.footerHeight, height + 0.001)
                    }
                }
                XCTAssertEqual(seen, Array(0..<count))
            }
        }
    }

    func testSmallWidgetLinksOneNotePerPageAndClampsAfterRemoval() {
        let small = WidgetPageLayout(count: 7, height: 150, single: true, requestedPage: 4)
        XCTAssertEqual(small.range, 4..<5)
        XCTAssertEqual(small.pageCount, 7)
        let fewer = WidgetPageLayout(count: 2, height: 150, single: true, requestedPage: 4)
        XCTAssertEqual(fewer.range, 1..<2)
        let empty = WidgetPageLayout(count: 0, height: 150, single: true, requestedPage: 4)
        XCTAssertEqual(empty.range, 0..<0)
    }
}
