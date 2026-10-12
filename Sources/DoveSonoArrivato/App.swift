import AppKit
import SwiftUI
import Carbon
import Combine

extension Notification.Name {
    // ⌘↩ in the panel: "Fatto" on the open post-it.
    static let postItAdvanceStep = Notification.Name("it.massimopozzi.postit.advance-step")
}

@main
struct DoveSonoArrivatoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { SettingsView() } }
}

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow {
            // Become key before dispatch so the same click edits text or presses a control.
            // A non-activating panel does this without switching apps: no activation delay,
            // and the app you were using keeps its menu bar and gets focus back on Esc.
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    // Handle ⌘Z / ⌘⇧Z here, before the menu: this menu-bar app has no visible Edit menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command, event.keyCode == 36 || event.keyCode == 76 { // Return, keypad Enter
            NotificationCenter.default.post(name: .postItAdvanceStep, object: self)
            return true
        }
        // While another app stays active its menu bar owns the shortcuts: route editing ones here.
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            let actions: [String: Selector] = ["x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                                               "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:))]
            if let action = actions[key], NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        if event.charactersIgnoringModifiers?.lowercased() == "z",
           let undoManager = firstResponder?.undoManager ?? undoManager {
            if flags == .command {
                if undoManager.canUndo { undoManager.undo() } else { NSSound.beep() }
                return true
            }
            if flags == [.command, .shift] {
                if undoManager.canRedo { undoManager.redo() } else { NSSound.beep() }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NotesPanel!
    private let store = NoteStore()
    private var shortcut: PanelShortcut?
    private var pendingURL: URL?
    private var panelHeight: CGFloat = 136
    private let reminders = ReminderScheduler()
    private var reminderSubscription: AnyCancellable?
    private var publishedLanguage: AppLanguage?

    override init() {
        super.init()
        registerEventHandlers()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        registerEventHandlers()
        // Before launch completes, so a click on a reminder that starts the app is delivered.
        reminders.activate()
    }

    private func registerEventHandlers() {
        // This app uses an AppKit panel and has no SwiftUI document/window scene
        // to receive onOpenURL. Handle the actual macOS URL event explicitly.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleReopen(_:reply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEReopenApplication))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerEventHandlers()
        UserDefaults.standard.register(defaults: ["hideAfterSave": true, "keepOnTop": true, "showAtLaunch": true, "staleAfterDays": 7])
        NotificationCenter.default.addObserver(self, selector: #selector(applyPreferences), name: UserDefaults.didChangeNotification, object: nil)
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "What’s Next?")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        panel = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "What’s Next?"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        // A fully zero-alpha backing can let WindowServer target the application
        // below while hosted layers redraw. A 1% backing keeps input on this panel.
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        applyPreferences()
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let maxHeight = min(680, (NSScreen.main?.visibleFrame.height ?? 800) - 32)
        let hosting = FirstClickHostingView(rootView: BoardView(store: store,
            hide: { [weak self] in self?.hidePanel() }, maxHeight: maxHeight,
            resize: { [weak self] height in self?.resizePanel(to: height) },
            beginReading: { [weak self] in self?.focusForReading() }))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        shortcut = PanelShortcut { [weak self] in self?.togglePanel() }
        UserDefaults.standard.set(shortcut?.isRegistered == true, forKey: "panelShortcutAvailable")
        observeWidgetActions()
        LoginItem.enableByDefaultOnce()
        reminders.open = { [weak self] url in self?.openPanel(for: url) }
        reminderSubscription = store.$notes.sink { [weak self] notes in self?.reminders.reconcile(notes) }
        if store.applyWidgetActions() == 0 { store.refreshWidgets() }
        if let url = pendingURL {
            pendingURL = nil
            openPanel(for: url)
        } else if UserDefaults.standard.bool(forKey: "showAtLaunch") { showPanel() }
    }

    // The widget's "Fatto" posts a Darwin notification after queueing its action.
    private func observeWidgetActions() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
                guard let observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in delegate.applyWidgetActions() }
            }, WidgetActions.notification as CFString, nil, .deliverImmediately)
    }

    func applyWidgetActions() {
        store.applyWidgetActions()
    }

    @objc private func applyPreferences() {
        panel?.level = UserDefaults.standard.bool(forKey: "keepOnTop") ? .floating : .normal
        statusItem?.button?.toolTip = L("What’s Next? — ⌃⌥Spazio", "What’s Next? — ⌃⌥Space")
        // Hand a language change to the widget and to pending reminder texts.
        let language = AppLanguage.current
        guard language != publishedLanguage else { return }
        publishedLanguage = language
        do { try AppLanguage.writeShared(language) } catch { NSLog("Widget language unavailable: %@", error.localizedDescription) }
        store.refreshWidgets()
        reminders.reconcile(store.notes)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { openPanel(for: url) }
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value) else { return }
        openPanel(for: url)
    }

    @objc private func handleReopen(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        if panel != nil { showPanel() }
    }

    private func openPanel(for url: URL) {
        guard let route = PanelRoute(url: url) else { return }
        guard panel != nil else { pendingURL = url; return }
        showPanel()
        var requested: WorkNote?
        switch route {
        case .new:
            var note = WorkNote()
            note.color = PaperColor(rawValue: UserDefaults.standard.string(forKey: "defaultPaperColor") ?? "yellow") ?? .yellow
            requested = note
        case .show:
            break
        case .note(let id):
            // A link to a note that is gone (deleted, or a widget placeholder): the panel
            // with the whole list is the useful answer, not an alert.
            requested = store.currentNote(id: id)
        }
        // Deliver only after the panel's hosting view has mounted its subscriptions.
        if let requested {
            DispatchQueue.main.async { [weak self] in self?.store.editRequest = requested }
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    private func resizePanel(to height: CGFloat) {
        guard let panel else { return }
        guard abs(panel.frame.height - ceil(height)) > 1 else { return }
        panelHeight = ceil(height)
        var frame = panel.frame
        frame.origin.y = frame.maxY - panelHeight
        frame.size.height = panelHeight
        panel.setFrame(frame, display: true)
    }

    private func hidePanel() {
        guard store.flushPendingEdits() else { return }
        store.refreshWidgets()
        panel.orderOut(nil)
    }

    private func focusForReading() {
        panel.makeFirstResponder(panel.contentView)
    }

    private func showPanel() {
        let wasHidden = !panel.isVisible
        if wasHidden { store.applyWidgetActions() }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let height = min(panelHeight, frame.height - 32)
            panel.setFrame(NSRect(x: frame.maxX - 376, y: frame.maxY - height - 16, width: 360, height: height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        if wasHidden { focusForReading() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.flushPendingEdits() else { return .terminateCancel }
        store.refreshWidgets(waitForWrite: true)
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
