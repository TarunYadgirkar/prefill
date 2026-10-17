import XCTest

// Long-press AutoFill with Prefill, on the iPhone itself (the Simulator never delivered inserted
// text): turns Prefill on in Settings' AutoFill & Passwords, inserts the first value Prefill
// offers into Notes' search field and checks it landed. Run with
// TEST_RUNNER_PREFILL_DEVICE_AUTOFILL=1 on a connected, unlocked phone.
@MainActor
final class AutoFillDeviceTests: XCTestCase {
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")

    override func setUp() async throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["PREFILL_DEVICE_AUTOFILL"] == "1" else {
            throw XCTSkip("Runs only on the iPhone, with PREFILL_DEVICE_AUTOFILL=1.")
        }
    }

    func testAValuePickedInAutoFillLandsInTheNote() throws {
        // Prefill shares its values with the keyboard and AutoFill when it opens.
        let app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 4)
        turnOnPrefill()

        // The notes list's search field: a plain text field, and nothing is written to a note.
        notes.launch()
        let back = notes.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        let body = notes.searchFields.firstMatch
        if !body.waitForExistence(timeout: 3) { notes.swipeDown() }
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Notes has no search field")
        body.tap()
        Thread.sleep(forTimeInterval: 1)
        body.tap()

        let autofill = notes.menuItems["AutoFill"]
        XCTAssertTrue(autofill.waitForExistence(timeout: 5), "no AutoFill in the edit menu: \(menu())")
        autofill.tap()
        let passwords = notes.buttons["Passwords"]
        if passwords.waitForExistence(timeout: 3) { passwords.tap() }
        let chooser = notes.buttons.matching(NSPredicate(format: "label == 'Prefill'")).firstMatch
        if chooser.waitForExistence(timeout: 5) { chooser.tap() }

        let cancel = notes.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Prefill's list never opened")
        let value = notes.buttons.allElementsBoundByIndex.first {
            !["Cancel", "Passwords"].contains($0.label) && $0.isHittable
        }
        let picked = try XCTUnwrap(value, "Prefill's list has no values")
        let text = picked.label
        picked.tap()
        Thread.sleep(forTimeInterval: 2)

        let typed = ((body.value as? String) ?? "").replacing("Search", with: "")
        attach(name: "note-after-insert")
        XCTAssertFalse(typed.isEmpty, "nothing landed in the field (picked \(text))")
    }

    // Settings' own search finds the page wherever this iOS keeps it.
    private func turnOnPrefill() {
        settings.terminate()
        settings.launch()
        let search = settings.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) { settings.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Settings has no search field")
        search.tap()
        search.typeText("AutoFill & Passwords")
        let result = settings.cells.containing(NSPredicate(format: "label CONTAINS 'AutoFill & Passwords'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "no AutoFill & Passwords result")
        result.tap()
        let prefill = NSPredicate(format: "identifier CONTAINS 'Prefill' OR label CONTAINS 'Prefill'")
        let toggle = settings.switches.matching(prefill).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Prefill isn't listed under AutoFill From")
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.tap() }
        Thread.sleep(forTimeInterval: 1)
        attach(name: "settings-autofill")
    }

    private func menu() -> [String] {
        notes.menuItems.allElementsBoundByIndex.map(\.label)
    }

    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
