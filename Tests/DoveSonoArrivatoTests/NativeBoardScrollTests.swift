import XCTest
import SwiftUI
import AppKit
@testable import DoveSonoArrivato

final class NativeBoardScrollTests: XCTestCase {
    @MainActor
    private func content(rows: Int) -> AnyView {
        AnyView(VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                PaperTextEditor(text: .constant("Testo del post-it"), placeholder: "", label: "Testo")
                    .frame(height: 100)
            }
        }.fixedSize(horizontal: false, vertical: true))
    }

    @MainActor
    func testRealDocumentHeightAndPositionSurviveRepeatedEditorUpdates() {
        let scroll = BoardNativeScrollView(content: content(rows: 12), heightChanged: { _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.documentView!.frame.height, 1200, accuracy: 1)
        XCTAssertTrue(scroll.documentView!.isFlipped)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        for _ in 0..<20 {
            scroll.update(content: content(rows: 12), selectedID: nil)
            scroll.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.contentView.bounds.minY, 400, accuracy: 1)
        }
        // Collapsing notes clamps at the new bottom instead of leaving an unreachable region.
        scroll.update(content: content(rows: 4), selectedID: nil)
        scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.documentView!.frame.height, 400, accuracy: 1)
        XCTAssertLessThanOrEqual(scroll.contentView.bounds.minY, 100)
    }

    @MainActor
    func testEditorKeepsFocusAndSelectionAcrossHostingUpdates() {
        let scroll = BoardNativeScrollView(content: content(rows: 3), heightChanged: { _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        scroll.layoutSubtreeIfNeeded()
        func firstEditor(in view: NSView) -> PaperTextView? {
            if let field = view as? PaperTextView { return field }
            return view.subviews.lazy.compactMap { firstEditor(in: $0) }.first
        }
        let field = firstEditor(in: scroll.documentView!)!
        XCTAssertTrue(window.makeFirstResponder(field))
        field.setSelectedRange(NSRange(location: 2, length: 5))
        for _ in 0..<20 {
            scroll.update(content: content(rows: 3), selectedID: nil)
            scroll.layoutSubtreeIfNeeded()
            XCTAssertTrue(firstEditor(in: scroll.documentView!) === field)
            XCTAssertTrue(window.firstResponder === field)
            XCTAssertEqual(field.selectedRange(), NSRange(location: 2, length: 5))
        }
    }

    @MainActor
    func testDropGeometryUsesActualOverlappingCardsAtAnyScrollPosition() {
        let ids = (0..<12).map { _ in UUID() }
        let content = AnyView(VStack(spacing: -18) {
            ForEach(ids, id: \.self) { id in
                Color.yellow.frame(height: 100)
                    .background(BoardScrollMarker(id: id))
            }
        }.fixedSize(horizontal: false, vertical: true))
        let scroll = BoardNativeScrollView(content: content, heightChanged: { _ in })
        scroll.frame = NSRect(x: 0, y: 0, width: 360, height: 300)
        scroll.layoutSubtreeIfNeeded()
        let initial = scroll.dragRows().sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(initial.map(\.id), ids)
        XCTAssertEqual(initial.last!.frame.minY, 902, accuracy: 1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        XCTAssertEqual(scroll.dragRows().sorted { $0.frame.minY < $1.frame.minY }.map(\.frame), initial.map(\.frame))
        let destination = NoteDragPlacement.resolve(y: 1020, rows: scroll.dragRows())
        XCTAssertEqual(destination?.target, ids.last)
        XCTAssertEqual(destination?.after, true)
    }

    @MainActor
    func testNativeEditorsBelongToTheSingleScrollContainer() {
        let scroll = BoardNativeScrollView(content: content(rows: 6), heightChanged: { _ in })
        scroll.frame = NSRect(x: 0, y: 0, width: 360, height: 300)
        scroll.layoutSubtreeIfNeeded()
        func editors(in view: NSView) -> [PaperTextView] {
            (view as? PaperTextView).map { [$0] } ?? view.subviews.flatMap { editors(in: $0) }
        }
        let fields = editors(in: scroll.documentView!)
        XCTAssertEqual(fields.count, 6)
        XCTAssertTrue(fields.allSatisfy { $0.enclosingScrollView === scroll })
    }
}
