import AppKit
import SwiftUI

private final class BoardDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// One native scroll container owns the document, its height, trackpad phases and momentum.
// Hosting the complete stack here keeps native text editors in the same responder hierarchy.
struct NativeBoardScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let selectedID: UUID?
    let contentHeightChanged: (CGFloat) -> Void
    let moveNote: (UUID, UUID, Bool) -> Void

    init(selectedID: UUID?, contentHeightChanged: @escaping (CGFloat) -> Void,
         moveNote: @escaping (UUID, UUID, Bool) -> Void,
         @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selectedID = selectedID
        self.contentHeightChanged = contentHeightChanged
        self.moveNote = moveNote
    }

    func makeNSView(context: Context) -> BoardNativeScrollView<Content> {
        BoardNativeScrollView(content: content, heightChanged: contentHeightChanged)
    }
    func updateNSView(_ view: BoardNativeScrollView<Content>, context: Context) {
        view.heightChanged = contentHeightChanged
        view.moveNote = moveNote
        view.update(content: content, selectedID: selectedID)
    }
}

final class BoardNativeScrollView<Content: View>: NSScrollView {
    private let host: NSHostingController<Content>
    private let document = BoardDocumentView()
    var heightChanged: (CGFloat) -> Void
    private var needsMeasurement = true
    private var measuredWidth: CGFloat = 0
    private var measuredHeight: CGFloat = 0
    private var measuring = false
    private var selectedID: UUID?
    // The sheet just opened, kept in view while the panel grows around it.
    private var revealID: UUID?
    var moveNote: ((UUID, UUID, Bool) -> Void)?
    private var dragSource: UUID?
    private var dragPoint: NSPoint?
    private var placement: NoteDragPlacement?
    private var scrollTimer: Timer?
    private let insertionLine = DropInsertionLine()


    init(content: Content, heightChanged: @escaping (CGFloat) -> Void) {
        host = NSHostingController(rootView: content)
        self.heightChanged = heightChanged
        super.init(frame: .zero)
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .none
        host.sizingOptions = []
        document.addSubview(host.view)
        documentView = document
        registerForDraggedTypes([PaperOpenArea.OpenView.pasteboardType])
        insertionLine.wantsLayer = true
        insertionLine.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        insertionLine.layer?.cornerRadius = 2
        insertionLine.isHidden = true
        addSubview(insertionLine)

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: Content, selectedID: UUID?) {
        host.rootView = content
        needsMeasurement = true
        if self.selectedID != selectedID {
            self.selectedID = selectedID
            revealID = selectedID
            // The panel resizes over the next few layout passes; stop following after that.
            if let selectedID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    if self?.revealID == selectedID { self?.revealID = nil }
                }
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard !measuring, contentSize.width > 0 else { return }
        measuring = true
        defer { measuring = false }
        let width = contentSize.width
        if needsMeasurement || abs(width - measuredWidth) > 0.5 {
            needsMeasurement = false
            measuredWidth = width
            let height = ceil(host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            let previousOrigin = contentView.bounds.origin
            document.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.view.frame = document.bounds
            host.view.layoutSubtreeIfNeeded()
            // Only clamp when the document shrinks. Never reset position on an edit or wheel event.
            if previousOrigin.y > max(0, height - contentSize.height) {
                contentView.scroll(to: NSPoint(x: 0, y: max(0, height - contentSize.height)))
                reflectScrolledClipView(contentView)
            }
            if abs(measuredHeight - height) > 0.5 {
                measuredHeight = height
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.measuredHeight == height else { return }
                    self.heightChanged(height)
                }
            }
        }
        if let id = revealID, let marker = findMarker(id, in: host.view) {
            reveal(marker.convert(marker.bounds, to: document))
        }
    }

    // Show the whole open sheet, the last one included. When it is taller than the
    // panel its title wins. A sheet already in view does not move.
    private func reveal(_ rect: NSRect) {
        let visible = contentView.bounds
        var y = visible.minY
        if rect.maxY > visible.maxY { y = rect.maxY - visible.height }
        if rect.minY < y { y = rect.minY }
        y = min(max(0, y), max(0, document.frame.height - visible.height))
        guard abs(y - visible.minY) > 0.5 else { return }
        contentView.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
        revealID = nil // the person is scrolling: never fight them
        super.scrollWheel(with: event)
    }

    func dragRows() -> [NoteDragRow] {
        var rows: [NoteDragRow] = []
        func collect(_ view: NSView) {
            if let name = view.identifier?.rawValue,
               name.hasPrefix("postit-scroll-"),
               let id = UUID(uuidString: String(name.dropFirst("postit-scroll-".count))) {
                rows.append(NoteDragRow(id: id, frame: view.convert(view.bounds, to: document)))
            }
            for child in view.subviews { collect(child) }
        }
        collect(host.view)
        return rows
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }
    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let raw = sender.draggingPasteboard.string(forType: PaperOpenArea.OpenView.pasteboardType),
              let id = UUID(uuidString: raw), dragRows().contains(where: { $0.id == id }) else {
            clearDrag()
            return []
        }
        dragSource = id
        dragPoint = sender.draggingLocation
        updateInsertion()
        if scrollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.scrollDrag() }
            scrollTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        return .move
    }
    private func updateInsertion() {
        guard let point = dragPoint else { return }
        placement = NoteDragPlacement.resolve(y: document.convert(point, from: nil).y, rows: dragRows())
        guard let placement else { insertionLine.isHidden = true; return }
        let seam = convert(NSPoint(x: 0, y: placement.indicatorY), from: document)
        let viewport = contentView.frame
        insertionLine.frame = NSRect(x: viewport.minX + 10,
                                    y: min(max(seam.y - 2, viewport.minY), viewport.maxY - 4),
                                    width: max(0, viewport.width - 20), height: 4)
        insertionLine.isHidden = false
    }
    private func scrollDrag() {
        guard let point = dragPoint, window != nil else { clearDrag(); return }
        let clip = contentView
        let local = clip.convert(point, from: nil)
        let y = clip.isFlipped ? local.y - clip.bounds.minY : clip.bounds.maxY - local.y
        let delta = NoteDragPlacement.scrollDelta(y: y, viewportHeight: clip.bounds.height)
        guard delta != 0 else { return }
        let next = min(max(0, clip.bounds.minY + delta), max(0, document.frame.height - clip.bounds.height))
        if next != clip.bounds.minY {
            clip.scroll(to: NSPoint(x: 0, y: next))
            reflectScrolledClipView(clip)
            updateInsertion()
        }
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearDrag() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { dragSource != nil && placement != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Commit the insertion shown during the drag. Re-reading the mouse location
        // at mouse-up can jump the destination after scrolling or pointer restoration.
        guard let source = dragSource, let destination = placement else { clearDrag(); return false }
        clearDrag()
        if source != destination.target { moveNote?(source, destination.target, destination.after) }
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { clearDrag() }
    override func draggingEnded(_ sender: NSDraggingInfo) { clearDrag() }
    private func clearDrag() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        dragSource = nil
        dragPoint = nil
        placement = nil
        insertionLine.isHidden = true
    }

    private func findMarker(_ id: UUID, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == "postit-scroll-\(id.uuidString)" { return view }
        for child in view.subviews {
            if let match = findMarker(id, in: child) { return match }
        }
        return nil
    }
}

struct BoardScrollMarker: NSViewRepresentable {
    let id: UUID
    private final class Marker: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView { Marker(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("postit-scroll-\(id.uuidString)")
    }
}

private final class DropInsertionLine: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}
