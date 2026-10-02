import XCTest

// Safari's Prefill sheet, run by scripts/test.sh e2e after a host test has linked the Alex
// Rivera card. Picking the work email in the sheet should put it first in Safari's own bar
// the next time the email field is focused.
@MainActor
final class PopupE2ETests: XCTestCase {
    private let workEmail = "alex@work.example.org"

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testPickingAValueInTheSheetPutsItFirstInSafarisBar() {
        XCUIApplication().launch()
        SafariDriver.enableExtension()
        SafariDriver.open(E2EServer.Site.siteA.page("contact.html"), waitingFor: "Email")
        Thread.sleep(forTimeInterval: 3)

        SafariDriver.openPrefillSheet()
        let pick = SafariDriver.safari.buttons["Use \(workEmail) on this site"].firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 20), "the sheet never offered the work email")
        pick.tap()
        let done = SafariDriver.safari.staticTexts["Done. Tap the field again to see it first."].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "the sheet never confirmed the pick")
        Thread.sleep(forTimeInterval: 0.8)
        E2EServer.screenshot("popup-sheet")
        SafariDriver.closeSheet(from: SafariDriver.safari.staticTexts["Safari will suggest on"].firstMatch)

        var slots: [String] = []
        for _ in 0..<3 {
            slots = SafariDriver.suggestions(focusing: "Email")
            if slots.first?.hasSuffix(workEmail) == true { break }
            SafariDriver.dismissKeyboard()
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertTrue(slots.first?.hasSuffix(workEmail) == true, "QuickType bar after the pick: \(slots)")
    }
}
