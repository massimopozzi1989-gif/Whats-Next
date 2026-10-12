import XCTest
import SwiftUI
import AppKit
@testable import DoveSonoArrivato

final class OpenLastNoteTests: XCTestCase {
    @MainActor
    func testOpeningTheLastNoteRevealsTheWholeSheet() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = NoteStore(fileURL: file)
        for index in 0..<10 {
            var note = WorkNote()
            note.title = "Lavoro \(index)"
            note.progress = String(repeating: "Una frase lunga da cui ripartire. ", count: 3)
            note.nextStep = "Il passo successivo"
            XCTAssertTrue(store.save(note))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 136),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = FirstClickHostingView(rootView: BoardView(store: store, hide: {}, maxHeight: 680,
            resize: { height in
                var frame = window.frame
                frame.origin.y = frame.maxY - height
                frame.size.height = height
                window.setFrame(frame, display: true)
            }, beginReading: {}))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        func pump() {
            for _ in 0..<40 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                hosting.layoutSubtreeIfNeeded()
            }
        }
        pump()
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let last = try XCTUnwrap(store.orderedNotes.last)
        store.editRequest = last
        pump()
        let scroll = try XCTUnwrap(scrollView(in: hosting))
        func marker(_ id: UUID, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == "postit-scroll-\(id.uuidString)" { return view }
            return view.subviews.lazy.compactMap { marker(id, in: $0) }.first
        }
        let sheet = try XCTUnwrap(marker(last.id, in: scroll))
        let card = sheet.convert(sheet.bounds, to: scroll.contentView)
        let visible = scroll.contentView.bounds
        XCTAssertLessThan(card.height, visible.height, "the open sheet fits the panel")
        XCTAssertGreaterThanOrEqual(card.minY, visible.minY - 1, "top of the open sheet is visible")
        XCTAssertLessThanOrEqual(card.maxY, visible.maxY + 1, "bottom of the open sheet is visible")
    }
}
