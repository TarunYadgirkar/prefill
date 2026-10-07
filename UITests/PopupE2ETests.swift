import XCTest

// Safari's Prefill sheet, run by scripts/test.sh e2e after a host test has linked the Alex
// Rivera card. Picking the work email in the sheet should put it first in Prefill's list under
// the email field the next time it's focused, without changing the card.
@MainActor
final class PopupE2ETests: XCTestCase {
    private let workEmail = "alex@work.example.org"

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testPickingAValueInTheSheetPutsItFirstInPrefillsList() {
        XCUIApplication().launch()
        SafariDriver.enableExtension()
        SafariDriver.open(E2EServer.Site.siteA.page("contact.html"), waitingFor: "Email")
        Thread.sleep(forTimeInterval: 3)

        SafariDriver.openPrefillSheet()
        let pick = SafariDriver.safari.buttons["Use \(workEmail) first on this site"].firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 20), "the sheet never offered the work email")
        pick.tap()
        let done = SafariDriver.safari.staticTexts["Done. Tap the field again to see it first."].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "the sheet never confirmed the pick")
        Thread.sleep(forTimeInterval: 0.8)
        E2EServer.screenshot("popup-sheet")
        SafariDriver.closeSheet(from: SafariDriver.safari.staticTexts["First on this site"].firstMatch)

        let rows = [
            SafariDriver.Row(value: workEmail, detail: "Used here"),
            SafariDriver.Row(value: "alex.rivera@example.com", detail: "Home email"),
            SafariDriver.Row(value: "alex.school@example.edu", detail: "Email")
        ]
        let shown = SafariDriver.prefillList(focusing: "Email", rows: rows)
        XCTAssertEqual(shown.first, workEmail, "Prefill's list after the pick: \(shown)")
        XCTAssertEqual(E2EServer.card()?.emails.first, "alex.rivera@example.com", "the pick rewrote the card")
    }
}
