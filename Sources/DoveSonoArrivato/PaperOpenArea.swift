import AppKit
import SwiftUI

struct PaperOpenArea: NSViewRepresentable {
    let id: UUID
    let title: String
    let color: PaperColor
    let open: () -> Void
    var opensOnClick = true
    // Right-click on the paper: quick actions such as the priority sticker or deleting.
    var contextItems: [ContextItem] = []
    // Drop a folder from Finder or a URL from the browser onto the paper.
    var onDropLink: ((String) -> Void)?

    struct ContextItem {
        let title: String
        let action: () -> Void
        var isSeparator = false

        static func separator() -> ContextItem {
            ContextItem(title: "", action: {}, isSeparator: true)
        }
    }

    func makeNSView(context: Context) -> OpenView { OpenView(frame: .zero) }
    func updateNSView(_ view: OpenView, context: Context) {
        view.noteID = id
        view.title = title
        view.paperColor = NSColor(color.paper)
        view.open = open
        view.opensOnClick = opensOnClick
        view.contextItems = contextItems
        view.onDropLink = onDropLink
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(opensOnClick ? .button : .image)
        view.setAccessibilityLabel(title)
        view.setAccessibilityHelp(opensOnClick ? L("Clicca per aprire; trascina per riordinare", "Click to open; drag to reorder")
                                               : L("Trascina per riordinare", "Drag to reorder"))
    }

    final class OpenView: NSView, NSDraggingSource {
        static let pasteboardType = NSPasteboard.PasteboardType("it.massimopozzi.postit.note-order")
        var noteID = UUID()
        var title = ""
        var paperColor = NSColor.yellow
        var open: (() -> Void)?
        var opensOnClick = true
        var contextItems: [ContextItem] = []
        var onDropLink: ((String) -> Void)?
        private var start = NSPoint.zero
        private var isDragging = false
        private var didDrag = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL, .URL, .string])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override var needsPanelToBecomeKey: Bool { true }
        override func mouseDown(with event: NSEvent) {
            start = convert(event.locationInWindow, from: nil)
            isDragging = false
            didDrag = false
            // AppKit delivers mouseDragged/mouseUp normally. Do not block the
            // application's event loop while deciding between a click and a drag.
        }
        override func mouseDragged(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            guard !isDragging, hypot(location.x - start.x, location.y - start.y) > 4 else { return }
            isDragging = true
            didDrag = true
            let pasteboard = NSPasteboardItem()
            pasteboard.setString(noteID.uuidString, forType: Self.pasteboardType)
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let previewSize = NSSize(width: max(240, bounds.width), height: max(64, bounds.height))
            let image = NSImage(size: previewSize, flipped: false) { rect in
                self.paperColor.withAlphaComponent(0.95).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                (self.title as NSString).draw(in: rect.insetBy(dx: 24, dy: 20), withAttributes: [
                    .font: NSFont(name: "Noteworthy-Bold", size: 21) ?? NSFont.boldSystemFont(ofSize: 21),
                    .foregroundColor: NSColor.darkGray
                ])
                return true
            }
            let frame = opensOnClick ? bounds : NSRect(x: start.x - 24, y: start.y - 32, width: previewSize.width, height: previewSize.height)
            item.setDraggingFrame(frame, contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
        }
        override func mouseUp(with event: NSEvent) {
            if opensOnClick && !didDrag && !isDragging && bounds.contains(convert(event.locationInWindow, from: nil)) { open?() }
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            guard !contextItems.isEmpty else { return nil }
            let menu = NSMenu()
            for (index, entry) in contextItems.enumerated() {
                if entry.isSeparator {
                    menu.addItem(.separator())
                } else {
                    let item = NSMenuItem(title: entry.title, action: #selector(runContextItem(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    menu.addItem(item)
                }
            }
            return menu
        }
        @objc private func runContextItem(_ sender: NSMenuItem) {
            guard contextItems.indices.contains(sender.tag) else { return }
            contextItems[sender.tag].action()
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { isDragging = false }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard onDropLink != nil,
                  sender.draggingPasteboard.string(forType: Self.pasteboardType) == nil,
                  WorkLink.droppedLink(from: sender.draggingPasteboard) != nil else { return [] }
            return .link
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            draggingEntered(sender)
        }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let onDropLink,
                  sender.draggingPasteboard.string(forType: Self.pasteboardType) == nil,
                  let link = WorkLink.droppedLink(from: sender.draggingPasteboard) else { return false }
            onDropLink(link)
            return true
        }

        override func accessibilityPerformPress() -> Bool {
            guard opensOnClick else { return false }
            open?()
            return true
        }
    }
}
