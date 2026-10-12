import AppKit
import SwiftUI

// A native editor receives the activating click itself, rather than relying on
// the hosting view to forward it to SwiftUI's multiline text field.
final class PaperTextView: NSTextView {
    var placeholder = ""
    var focusWhenAttached = false
    private var scheduledInitialFocus = false
    private var receivedMouse = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfRequested()
    }

    func focusIfRequested() {
        guard focusWhenAttached, !scheduledInitialFocus, window != nil else { return }
        scheduledInitialFocus = true
        guard !receivedMouse, let window, !(window.firstResponder is NSTextView) else { return }
        window.makeFirstResponder(self)
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        receivedMouse = true
        if let window, !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // The editor grows with its text; the enclosing board owns all scrolling.
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return
            }
            ancestor = view.superview
        }
        super.scrollWheel(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(in: bounds.insetBy(dx: 0, dy: 6), withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor(red: 0.19, green: 0.22, blue: 0.19, alpha: 0.45)
            ])
        }
    }
}

struct PaperTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let label: String
    var fontSize: CGFloat = 18
    var bold = false
    var focusNewTitle = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PaperTextView {
        // Build on TextKit 1 directly. A TextKit 2 view silently rebuilds its whole
        // text system the first time its layoutManager is touched, on every card open.
        let view = PaperTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 0, height: 6)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.allowsUndo = true
        view.insertionPointColor = Self.ink
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PaperTextView, context: Context) {
        context.coordinator.parent = self
        let desiredFont = Self.font(size: fontSize, bold: bold)
        if view.font != desiredFont { view.font = desiredFont }
        let ink = Self.ink
        if view.textColor != ink { view.textColor = ink }
        if view.string.isEmpty && view.typingAttributes[.foregroundColor] == nil {
            view.typingAttributes = [.font: desiredFont, .foregroundColor: ink]
        }
        if view.placeholder != placeholder {
            view.placeholder = placeholder
            view.needsDisplay = true
        }
        if view.accessibilityLabel() != label { view.setAccessibilityLabel(label) }
        // Never replace the text storage on an autosave echo: that would reset
        // the selection while the user is dragging or deleting part of a line.
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            // Fatto or ⌘Z rewrote this field: start a fresh typing undo group afterwards.
            view.breakUndoCoalescing()
            view.needsDisplay = true
            let length = (text as NSString).length
            let location = min(selection.location, length)
            view.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        }
        view.focusWhenAttached = focusNewTitle
        view.focusIfRequested()

    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PaperTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 280)
        let font = nsView.font ?? .systemFont(ofSize: fontSize)
        let coordinator = context.coordinator
        if coordinator.measuredText == text, coordinator.measuredPlaceholder == placeholder,
           coordinator.measuredWidth == width, coordinator.measuredFont == font {
            return coordinator.measuredSize
        }
        let sample = text.isEmpty ? placeholder : (text.hasSuffix("\n") ? text + " " : text)
        let bounds = (sample as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let lineHeight = Self.lineHeight(for: font)
        let size = CGSize(width: width, height: max(44, ceil(lineHeight) + 12, ceil(bounds.height) + 12))
        coordinator.measuredText = text
        coordinator.measuredPlaceholder = placeholder
        coordinator.measuredWidth = width
        coordinator.measuredFont = font
        coordinator.measuredSize = size
        return size
    }

    static let ink = NSColor(red: 0.19, green: 0.22, blue: 0.19, alpha: 1)
    private static var fonts: [String: NSFont] = [:]
    private static var lineHeights: [NSFont: CGFloat] = [:]
    private static let measuringLayout = NSLayoutManager()

    static func font(size: CGFloat, bold: Bool) -> NSFont {
        let key = "\(bold ? "b" : "l")\(size)"
        if let font = fonts[key] { return font }
        let font = NSFont(name: bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size)
            ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
        fonts[key] = font
        return font
    }

    private static func lineHeight(for font: NSFont) -> CGFloat {
        if let height = lineHeights[font] { return height }
        let height = measuringLayout.defaultLineHeight(for: font)
        lineHeights[font] = height
        return height
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var measuredText: String?
        var measuredPlaceholder: String?
        var measuredWidth: CGFloat?
        var measuredFont: NSFont?
        var measuredSize: CGSize?
        var parent: PaperTextEditor
        init(_ parent: PaperTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? PaperTextView else { return }
            parent.text = view.string
            // The binding requests SwiftUI layout; avoid a second invalidation per key.
        }
    }
}
