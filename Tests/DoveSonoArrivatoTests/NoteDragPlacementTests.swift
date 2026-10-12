import XCTest
@testable import DoveSonoArrivato

final class NoteDragPlacementTests: XCTestCase {
    func testOverlappingPaperAndFooterReachEveryInsertionPosition() {
        let ids = (0..<4).map { _ in UUID() }
        let rows = ids.enumerated().map { NoteDragRow(id: $0.element, frame: CGRect(x: 10, y: $0.offset * 82, width: 340, height: 100)) }
        XCTAssertEqual(NoteDragPlacement.resolve(y: -10, rows: rows)?.target, ids[0])
        // The bottom half of each visible strip selects the seam before the next paper.
        for index in 0..<3 {
            let destination = NoteDragPlacement.resolve(y: CGFloat(index * 82 + 60), rows: rows)
            XCTAssertEqual(destination?.target, ids[index + 1])
            XCTAssertEqual(destination?.after, false)
            XCTAssertEqual(destination?.indicatorY, CGFloat((index + 1) * 82))
        }
        let bottom = NoteDragPlacement.resolve(y: 390, rows: rows)
        XCTAssertEqual(bottom?.target, ids.last)
        XCTAssertEqual(bottom?.after, true)
        XCTAssertNil(NoteDragPlacement.resolve(y: 100, rows: []))
    }

    func testExpandedPaperHasBothDropPositionsAndAutoscrollAcceleratesAtEdges() {
        let first = UUID(), second = UUID()
        let rows = [NoteDragRow(id: first, frame: CGRect(x: 0, y: 0, width: 360, height: 450)),
                    NoteDragRow(id: second, frame: CGRect(x: 0, y: 432, width: 360, height: 100))]
        XCTAssertEqual(NoteDragPlacement.resolve(y: 100, rows: rows)?.target, first)
        XCTAssertEqual(NoteDragPlacement.resolve(y: 300, rows: rows)?.target, second)
        XCTAssertEqual(NoteDragPlacement.scrollDelta(y: 150, viewportHeight: 300), 0)
        XCTAssertLessThan(NoteDragPlacement.scrollDelta(y: 0, viewportHeight: 300), NoteDragPlacement.scrollDelta(y: 30, viewportHeight: 300))
        XCTAssertGreaterThan(NoteDragPlacement.scrollDelta(y: 300, viewportHeight: 300), NoteDragPlacement.scrollDelta(y: 270, viewportHeight: 300))
    }
}
