import XCTest
import AppKit
import Carbon
import CoreSpotlight
@testable import DoveSonoArrivato

final class NewFeaturesTests: XCTestCase {
    override func tearDown() {
        AppLanguage.forced = nil
        super.tearDown()
    }

    func testFormattedTextIncludesTitleProgressNextStepLinkAndPath() {
        AppLanguage.forced = .english
        var note = WorkNote()
        note.title = "What’s Next"
        note.progress = "Shipped v1.3"
        note.action = .waiting
        note.nextStep = "App Store review"
        note.workLink = "https://example.com"
        note.history = [StepEntry(text: "Wrote tests", date: Date(timeIntervalSince1970: 1_700_000_000))]
        let text = note.formattedText()
        XCTAssertTrue(text.contains("What’s Next"))
        XCTAssertTrue(text.contains("Where I left off: Shipped v1.3"))
        XCTAssertTrue(text.contains("Waiting for: App Store review"))
        XCTAssertTrue(text.contains("Link: https://example.com"))
        XCTAssertTrue(text.contains("Path:"))
        XCTAssertTrue(text.contains("Wrote tests"))
    }

    func testDueReminderFlagOnlyMatchesOpenWaitingNotesWithPastReminder() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        var note = WorkNote()
        note.action = .waiting
        note.reminderAt = now.addingTimeInterval(-60)
        XCTAssertTrue(note.isDueReminder(now: now))

        note.reminderAt = now.addingTimeInterval(60)
        XCTAssertFalse(note.isDueReminder(now: now))

        note.reminderAt = now.addingTimeInterval(-60)
        note.action = .next
        XCTAssertFalse(note.isDueReminder(now: now))

        note.action = .waiting
        note.completedAt = now
        XCTAssertFalse(note.isDueReminder(now: now))
    }

    func testShortcutSpecSavesLoadsAndFormatsCorrectly() {
        let suiteName = "it.massimopozzi.dovesonoarrivato.shortcut-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguage.forced = .english
        XCTAssertEqual(ShortcutSpec.load(from: defaults), .defaultSpec)
        XCTAssertEqual(ShortcutSpec.defaultSpec.displayString, "⌃⌥Space")

        let custom = ShortcutSpec(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(cmdKey | shiftKey))
        custom.save(to: defaults)
        XCTAssertEqual(ShortcutSpec.load(from: defaults), custom)
        XCTAssertEqual(custom.displayString, "⇧⌘N")

        ShortcutSpec.reset(in: defaults)
        XCTAssertEqual(ShortcutSpec.load(from: defaults), .defaultSpec)
    }

    func testWorkLinkExtractsDroppedURLsAndFoldersFromPasteboard() {
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.setString("https://example.com/docs", forType: .string)
        XCTAssertEqual(WorkLink.droppedLink(from: pb), "https://example.com/docs")
        XCTAssertFalse(WorkLink.isFolder("https://example.com/docs"))

        pb.clearContents()
        pb.setString("/Users/example/Project", forType: .string)
        XCTAssertEqual(WorkLink.droppedLink(from: pb), "/Users/example/Project")
        XCTAssertTrue(WorkLink.isFolder("/Users/example/Project"))
    }

    func testSpotlightItemAndActivityRoundTrip() {
        var note = WorkNote()
        note.title = "Progetto Spotlight"
        note.progress = "Indicizzazione pronta"
        note.nextStep = "Testare apertura"
        let item = SpotlightIndexer.searchableItem(for: note)
        XCTAssertEqual(item.uniqueIdentifier, WidgetSnapshot.link(note).absoluteString)
        XCTAssertEqual(item.attributeSet.title, "Progetto Spotlight")

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: item.uniqueIdentifier]
        XCTAssertEqual(SpotlightIndexer.noteID(from: activity), note.id)
    }

    @MainActor
    func testPanelKeyEquivalentsForSearchCopyAndArrowNavigation() {
        let panel = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false

        let searchExp = expectation(forNotification: .postItToggleSearch, object: panel)
        let fEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                      windowNumber: panel.windowNumber, context: nil, characters: "f",
                                      charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
        XCTAssertTrue(panel.performKeyEquivalent(with: fEvent))

        let copyExp = expectation(forNotification: .postItCopyNote, object: panel)
        let cEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                      windowNumber: panel.windowNumber, context: nil, characters: "C",
                                      charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        XCTAssertTrue(panel.performKeyEquivalent(with: cEvent))

        let navExp = expectation(forNotification: .postItNavigateKey, object: panel)
        let downEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: panel.windowNumber, context: nil, characters: "",
                                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)!
        panel.keyDown(with: downEvent)

        wait(for: [searchExp, copyExp, navExp], timeout: 1)
    }
}
