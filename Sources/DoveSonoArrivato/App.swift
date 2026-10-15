import AppKit
import SwiftUI
import Carbon
import Combine

extension Notification.Name {
    // ⌘↩ in the panel: "Fatto" on the open post-it.
    static let postItAdvanceStep = Notification.Name("it.massimopozzi.postit.advance-step")
    // ⌘F in the panel: open/focus the search bar.
    static let postItToggleSearch = Notification.Name("it.massimopozzi.postit.toggle-search")
    // ⌘⇧C in the panel: copy the open or selected note as plain text.
    static let postItCopyNote = Notification.Name("it.massimopozzi.postit.copy-note")
    // ↑ / ↓ / ↩ when no text editor is focused: navigate and toggle sheets.
    static let postItNavigateKey = Notification.Name("it.massimopozzi.postit.navigate-key")
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

    // Handle ⌘Z / ⌘⇧Z and panel shortcuts here, before the menu: this menu-bar app has no visible Edit menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command, event.keyCode == 36 || event.keyCode == 76 { // Return, keypad Enter
            NotificationCenter.default.post(name: .postItAdvanceStep, object: self)
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            NotificationCenter.default.post(name: .postItToggleSearch, object: self)
            return true
        }
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
            NotificationCenter.default.post(name: .postItCopyNote, object: self)
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

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags.isEmpty, !(firstResponder is NSTextView) {
            if event.keyCode == 125 || event.keyCode == 126 || event.keyCode == 36 || event.keyCode == 76 {
                NotificationCenter.default.post(name: .postItNavigateKey, object: self, userInfo: ["keyCode": event.keyCode])
                return
            }
        }
        super.keyDown(with: event)
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
    private var badgeTimer: Timer?
    private var publishedLanguage: AppLanguage?
    private var lastShortcutSpec: ShortcutSpec?

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
        UserDefaults.standard.register(defaults: ["keepOnTop": true, "showAtLaunch": true, "staleAfterDays": 7])
        NotificationCenter.default.addObserver(self, selector: #selector(applyPreferences), name: UserDefaults.didChangeNotification, object: nil)
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "What’s Next?")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

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
        let initialSpec = ShortcutSpec.load()
        lastShortcutSpec = initialSpec
        shortcut = PanelShortcut(spec: initialSpec) { [weak self] in self?.togglePanel() }
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
        observeWidgetActions()
        LoginItem.enableByDefaultOnce()
        reminders.open = { [weak self] url in self?.openPanel(for: url) }
        reminderSubscription = store.$notes.sink { [weak self] notes in
            self?.reminders.reconcile(notes)
            self?.updateStatusBadge(notes: notes)
        }
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusBadge(notes: self.store.notes)
            }
        }
        if store.applyWidgetActions() == 0 { store.refreshWidgets() }
        if let url = pendingURL {
            pendingURL = nil
            openPanel(for: url)
        } else if UserDefaults.standard.bool(forKey: "showAtLaunch") { showPanel() }
    }

    private func updateStatusBadge(notes: [WorkNote], now: Date = Date()) {
        let dueCount = notes.filter { $0.isDueReminder(now: now) }.count
        statusItem?.button?.title = dueCount > 0 ? "•" : ""
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
        let spec = ShortcutSpec.load()
        if spec != lastShortcutSpec {
            lastShortcutSpec = spec
            shortcut?.update(to: spec)
        }
        statusItem?.button?.toolTip = "What’s Next? — \(spec.displayString)"
        updateStatusBadge(notes: store.notes)
        // Hand a language change to the widget and to pending reminder texts.
        let language = AppLanguage.current
        guard language != publishedLanguage else { return }
        publishedLanguage = language
        do { try AppLanguage.writeShared(language) } catch { NSLog("Widget language unavailable: %@", error.localizedDescription) }
        store.refreshWidgets(force: true)
        reminders.reconcile(store.notes)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { openPanel(for: url) }
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        if let id = SpotlightIndexer.noteID(from: userActivity) {
            openPanel(for: URL(string: "dovesonoarrivato://note/\(id.uuidString)")!)
            return true
        }
        return false
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

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if isRightClick {
            showStatusItemMenu()
        } else {
            togglePanel()
        }
    }

    static func buildStatusItemMenu(isPanelVisible: Bool, target: AnyObject?) -> NSMenu {
        let menu = NSMenu()
        let toggleTitle = isPanelVisible
            ? L("Nascondi What’s Next?", "Hide What’s Next?")
            : L("Mostra What’s Next?", "Show What’s Next?")
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(togglePanel), keyEquivalent: "")
        toggleItem.target = target
        menu.addItem(toggleItem)

        let newItem = NSMenuItem(title: L("Nuovo post-it", "New note"), action: #selector(newNoteFromMenu), keyEquivalent: "n")
        newItem.target = target
        menu.addItem(newItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("Esci da What’s Next?", "Quit What’s Next?"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }

    private func showStatusItemMenu() {
        guard let button = statusItem.button else { return }
        let menu = Self.buildStatusItemMenu(isPanelVisible: panel?.isVisible == true, target: self)
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func newNoteFromMenu() {
        openPanel(for: URL(string: "dovesonoarrivato://new")!)
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
        updateStatusBadge(notes: store.notes)
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
