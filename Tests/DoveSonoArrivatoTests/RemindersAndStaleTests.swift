import XCTest
import AppKit
@testable import DoveSonoArrivato

final class RemindersAndStaleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testPresetsLandAtNineOnTheRightDay() {
        let now = date(2026, 10, 14, 16, 30) // Wednesday afternoon
        XCTAssertEqual(ReminderPreset.inOneHour.date(from: now, calendar: calendar), date(2026, 10, 14, 17, 30))
        XCTAssertEqual(ReminderPreset.tomorrow.date(from: now, calendar: calendar), date(2026, 10, 15, 9))
        XCTAssertEqual(ReminderPreset.inThreeDays.date(from: now, calendar: calendar), date(2026, 10, 17, 9))
        XCTAssertEqual(ReminderPreset.nextMonday.date(from: now, calendar: calendar), date(2026, 10, 19, 9))
        XCTAssertEqual(ReminderPreset.inOneWeek.date(from: now, calendar: calendar), date(2026, 10, 21, 9))
    }

    func testOnlyOpenWaitingNotesWithAFutureDateRing() {
        let now = date(2026, 10, 14)
        var waiting = WorkNote(); waiting.title = "Fattura"; waiting.action = .waiting
        waiting.nextStep = "Risposta del cliente"; waiting.reminderAt = date(2026, 10, 15, 9)
        var past = waiting; past.id = UUID(); past.reminderAt = date(2026, 10, 13, 9)
        var next = waiting; next.id = UUID(); next.action = .next
        var done = waiting; done.id = UUID(); done.completedAt = now
        AppLanguage.forced = .italian
        defer { AppLanguage.forced = nil }
        let requests = ReminderRequest.requests(for: [waiting, past, next, done], now: now)
        XCTAssertEqual(requests.map(\.identifier), ["reminder-\(waiting.id.uuidString)"])
        XCTAssertEqual(requests.first?.body, "In attesa: Risposta del cliente")
        AppLanguage.forced = .english
        XCTAssertEqual(ReminderRequest.requests(for: [waiting], now: now).first?.body, "Waiting for: Risposta del cliente")
        XCTAssertEqual(requests.first?.link, "dovesonoarrivato://note/\(waiting.id.uuidString)")
    }

    func testFattoEndsTheWaitAndItsReminder() {
        var note = WorkNote(); note.action = .waiting; note.nextStep = "Risposta"
        note.reminderAt = Date().addingTimeInterval(3600)
        XCTAssertTrue(note.advanceStep())
        XCTAssertNil(note.reminderAt)
        XCTAssertTrue(ReminderRequest.requests(for: [note]).isEmpty)
    }

    func testStaleNotesCountWholeDaysAndRespectTheThreshold() {
        let now = date(2026, 10, 14, 8)
        var note = WorkNote(); note.updatedAt = date(2026, 10, 6, 23)
        XCTAssertEqual(note.idleDays(now: now, calendar: calendar), 8)
        XCTAssertEqual(note.staleDays(threshold: 7, now: now, calendar: calendar), 8)
        XCTAssertNil(note.staleDays(threshold: 14, now: now, calendar: calendar))
        XCTAssertNil(note.staleDays(threshold: 0, now: now, calendar: calendar)) // "Mai"
        var completed = note; completed.completedAt = now
        XCTAssertNil(completed.staleDays(threshold: 7, now: now, calendar: calendar))
        // Waiting on purpose with a reminder still ahead: not forgotten.
        var waiting = note; waiting.action = .waiting; waiting.reminderAt = date(2026, 10, 20, 9)
        XCTAssertNil(waiting.staleDays(threshold: 7, now: now, calendar: calendar))
        waiting.reminderAt = date(2026, 10, 10, 9)
        XCTAssertEqual(waiting.staleDays(threshold: 7, now: now, calendar: calendar), 8)
    }

    func testCorruptQueuedWidgetActionsAreDropped() throws {
        let queue = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: queue) }
        try WidgetActions.enqueue(WidgetAdvanceAction(noteID: UUID(), step: "Passo", date: Date()), in: queue)
        let corrupt = queue.appendingPathComponent("rotto.json")
        try Data("{non è json".utf8).write(to: corrupt)
        XCTAssertEqual(WidgetActions.pending(in: queue).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))
    }

    @MainActor
    func testCommandReturnOnThePanelAsksTheOpenCardForFatto() {
        let panel = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let posted = expectation(forNotification: .postItAdvanceStep, object: panel)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                     windowNumber: panel.windowNumber, context: nil, characters: "\r",
                                     charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        wait(for: [posted], timeout: 1)
    }
}
