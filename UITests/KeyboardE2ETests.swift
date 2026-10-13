import XCTest

// The Prefill keyboard in Safari, run by scripts/test.sh e2e after a host test has linked
// the Alex Rivera card: with the keyboard added and Full Access on, a name field with no
// autocomplete hint (like Typeform's) offers the name first, and a tap types it.
@MainActor
final class KeyboardE2ETests: XCTestCase {
    private typealias Site = E2EServer.Site
    private let safari = SafariDriver.safari

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testANameFieldOffersTheNameFirst() {
        XCUIApplication().launch()
        Thread.sleep(forTimeInterval: 3)
        SafariDriver.enableKeyboard()
        SafariDriver.open(Site.siteA.page("application.html"), waitingFor: "First Name")
        SafariDriver.field("First Name").tap()
        XCTAssertTrue(switchToPrefill(), "the Prefill keyboard never came up")
        Thread.sleep(forTimeInterval: 1.5)
        E2EServer.screenshot("keyboard-first-name")

        let chips = safari.buttons.matching(NSPredicate(format: "label CONTAINS ', '")).allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
        // A pick from an earlier run puts First name ahead of Name, which is fine.
        XCTAssertEqual(Set(chips.prefix(2).map(\.label)), ["Alex Rivera, Name", "Alex, First name"])
        chips.first { $0.label == "Alex, First name" }?.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(SafariDriver.field("First Name").value as? String, "Alex")
    }

    // The globe key cycles keyboards; Prefill's shows the card's name as a chip.
    private func switchToPrefill() -> Bool {
        let chip = safari.buttons.matching(NSPredicate(format: "label ENDSWITH ', Name'")).firstMatch
        let globe = safari.buttons["Next keyboard"].firstMatch
        for _ in 0..<4 {
            if chip.waitForExistence(timeout: 2) { return true }
            guard globe.waitForExistence(timeout: 5) else { return false }
            globe.tap()
        }
        return chip.waitForExistence(timeout: 3)
    }
}
