import XCTest

// One-tap fill in Safari, run by scripts/test.sh e2e after a host test has linked the Alex
// Rivera card: the pill above the focused field, the sheet's Fill button, the other values
// on a filled field, declined demographic questions and Undo, on the Greenhouse-style
// application and on the React-Select one.
@MainActor
final class FillE2ETests: XCTestCase {
    private typealias Site = E2EServer.Site
    private let safari = SafariDriver.safari

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testOneTapFillsAnApplication() {
        XCUIApplication().launch()
        SafariDriver.enableExtension()
        SafariDriver.open(Site.siteA.page("application.html"), waitingFor: "First Name")
        Thread.sleep(forTimeInterval: 3)

        XCTContext.runActivity(named: "0. An empty field shows its own values under it, beside the pill") { _ in
            expectFieldList()
        }
        XCTContext.runActivity(named: "a. The pill sits above the field, clear of the keyboard, and fills") { _ in
            tapPill(focusing: "First Name", shot: "fill-a-pill")
            XCTAssertTrue(webButton("Undo").waitForExistence(timeout: 10), "the pill never offered Undo")
            E2EServer.screenshot("fill-a-filled")
            XCTAssertEqual(SafariDriver.field("First Name").value as? String, "Alex")
            XCTAssertEqual(SafariDriver.field("Email").value as? String, "alex.rivera@example.com")
        }
        XCTContext.runActivity(named: "b. Undo puts the form back") { _ in
            webButton("Undo").tap()
            Thread.sleep(forTimeInterval: 1)
            E2EServer.screenshot("fill-b-undone")
            XCTAssertEqual(SafariDriver.field("Email").value as? String ?? "", "")
            SafariDriver.dismissKeyboard()
        }
        XCTContext.runActivity(named: "c. The sheet's Fill button fills too") { _ in
            SafariDriver.openPrefillSheet()
            let fill = safari.buttons.matching(labelled("Fill [0-9]+ fields?")).firstMatch
            XCTAssertTrue(fill.waitForExistence(timeout: 20), "the sheet has no Fill button")
            fill.tap()
            let done = safari.staticTexts.matching(labelled("Filled [0-9]+ fields?\\..*")).firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 15), "the sheet never said it filled")
            E2EServer.screenshot("fill-c-sheet")
            SafariDriver.closeSheet(from: done)
            XCTAssertEqual(SafariDriver.field("Email").value as? String, "alex.rivera@example.com")
        }
        XCTContext.runActivity(named: "d. A tap on a filled field offers the other values") { _ in
            expectOtherValues()
        }
        XCTContext.runActivity(named: "e. Demographic questions are declined") { _ in
            expectDeclined()
        }
    }

    private func expectFieldList() {
        SafariDriver.field("Email").tap()
        let other = safari.webViews.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "alex@work.example.org")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 8), "the empty email field offered no list")
        XCTAssertTrue(pillButton().exists, "no Fill pill beside the list")
        E2EServer.screenshot("fill-0-field-list")
        SafariDriver.dismissKeyboard()
    }

    private func expectOtherValues() {
        SafariDriver.field("Email").tap()
        let other = safari.webViews.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "alex@work.example.org")).firstMatch
        let offered = other.waitForExistence(timeout: 8)
        E2EServer.screenshot("fill-d-other-values")
        if !offered { print("PREFILL-TREE \(safari.debugDescription)") }
        XCTAssertTrue(offered, "the filled email field never offered the work email")
        let field = SafariDriver.field("Email").frame
        XCTAssertFalse(other.frame.intersects(field), "the list covers its own field: \(other.frame) over \(field)")
        let keyboard = safari.keyboards.firstMatch.frame
        XCTAssertLessThanOrEqual(other.frame.maxY, keyboard.minY, "the list is under the keyboard")
        SafariDriver.dismissKeyboard()
    }

    private func expectDeclined() {
        safari.swipeUp()
        E2EServer.screenshot("fill-e-declined")
        let declined = [
            "Gender": "Decline To Self Identify", "Are you Hispanic/Latino?": "Decline To Self Identify",
            "Veteran Status": "I don't wish to answer", "Disability Status": "I do not want to answer"
        ]
        for (question, answer) in declined {
            XCTAssertEqual(safari.webViews.buttons[question].firstMatch.value as? String, answer, question)
        }
    }

    func testOneTapFillsReactSelectQuestions() {
        XCUIApplication().launch()
        SafariDriver.enableExtension()
        SafariDriver.open(Site.siteA.page("react-select/"), waitingFor: "First Name")
        Thread.sleep(forTimeInterval: 3)
        tapPill(focusing: "First Name", shot: "fill-react-pill")
        XCTAssertTrue(webButton("Undo").waitForExistence(timeout: 20), "the pill never offered Undo")
        SafariDriver.dismissKeyboard()
        safari.swipeUp()
        E2EServer.screenshot("fill-react-filled")
        for answer in ["Decline To Self Identify", "I don't wish to answer"] {
            XCTAssertTrue(safari.webViews.staticTexts[answer].firstMatch.exists, "no \(answer)")
        }
    }

    private func tapPill(focusing label: String, shot: String) {
        SafariDriver.field(label).tap()
        let pill = pillButton()
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "no Fill pill")
        Thread.sleep(forTimeInterval: 1)
        E2EServer.screenshot(shot)
        let keyboard = safari.keyboards.firstMatch
        if keyboard.exists {
            XCTAssertLessThanOrEqual(pill.frame.maxY, keyboard.frame.minY, "the keyboard covers the pill")
        }
        XCTAssertTrue(pill.isHittable, "the pill can't be tapped")
        pill.tap()
    }

    private func labelled(_ pattern: String) -> NSPredicate {
        NSPredicate(format: "label MATCHES %@", pattern)
    }

    private func pillButton() -> XCUIElement {
        safari.webViews.buttons.matching(labelled("Fill [0-9]+ fields with Prefill")).firstMatch
    }

    private func webButton(_ label: String) -> XCUIElement {
        safari.webViews.buttons[label].firstMatch
    }
}
