import XCTest
@testable import DoveSonoArrivato

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        AppLanguage.forced = nil
        super.tearDown()
    }

    func testSystemPreferenceFollowsTheFirstPreferredLanguage() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["it-IT", "en-US"]), .italian)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["en-GB", "it-IT"]), .english)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["de-DE"]), .english) // anything else: English
        XCTAssertEqual(AppLanguage.resolve(.italian, preferred: ["en-US"]), .italian)
        XCTAssertEqual(AppLanguage.resolve(.english, preferred: ["it-IT"]), .english)
    }

    func testLabelsSwitchWithoutChangingStoredValues() throws {
        AppLanguage.forced = .english
        XCTAssertEqual(NextAction.waiting.label, "Waiting for")
        XCTAssertEqual(PaperColor.mint.label, "Mint")
        AppLanguage.forced = .italian
        XCTAssertEqual(NextAction.waiting.label, "In attesa")
        // The persisted raw value stays Italian, so existing notes.json files keep decoding.
        var note = WorkNote(); note.action = .waiting
        let json = String(data: try JSONEncoder().encode(note), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"action\":\"In attesa\""))
    }

    func testReminderPresetsAndDatesFollowTheLanguage() {
        AppLanguage.forced = .english
        XCTAssertEqual(ReminderPreset.tomorrow.label, "Tomorrow at 9")
        let date = Date(timeIntervalSince1970: 1_791_000_000)
        let english = date.localized(.dateTime.month(.wide))
        AppLanguage.forced = .italian
        XCTAssertEqual(ReminderPreset.tomorrow.label, "Domani alle 9")
        XCTAssertNotEqual(date.localized(.dateTime.month(.wide)), english)
    }
}
