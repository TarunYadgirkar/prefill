import XCTest

// Custom fields end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=CustomFieldsE2ETests)
// after a host test has linked the Alex Rivera card: add the student starter set, with its school
// already filled in, from the You tab's Add menu, then focus the Greenhouse-style "School" field and read Prefill's
// list under it.
@MainActor
final class CustomFieldsE2ETests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    private let berkeley = "University of California, Berkeley"

    func testSchoolFieldOffersTheCustomAnswer() {
        SafariDriver.enableExtension()
        app.launchArguments = ["-finishedOnboarding", "YES"]
        app.launch()
        addSchool()
        E2EServer.screenshot("custom-card")
        app.terminate()

        SafariDriver.open(E2EServer.Site.siteA.page("greenhouse.html"), waitingFor: "School")
        Thread.sleep(forTimeInterval: 3)
        let listed = SafariDriver.prefillList(
            focusing: "School", rows: [SafariDriver.Row(value: berkeley, detail: "Custom field")]
        )
        E2EServer.screenshot("custom-field-list")
        XCTAssertEqual(listed.first, berkeley)
        SafariDriver.dismissKeyboard()
    }

    private func addSchool() {
        let tab = app.tabBars.buttons["You"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no You tab")
        tab.tap()
        app.buttons["add-menu"].firstMatch.tap()
        let starters = app.buttons["add-student-answers"].firstMatch
        XCTAssertTrue(starters.waitForExistence(timeout: 5), "no student answers in the Add menu")
        starters.tap()
        let school = app.textFields["student-school"]
        XCTAssertTrue(school.waitForExistence(timeout: 5), "no school answer")
        XCTAssertEqual(school.value as? String, berkeley)
        E2EServer.screenshot("custom-student-answers")
        app.buttons["save-student-answers"].tap()
        // Answers sit below the card's contact values, so search brings School on screen.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search field")
        search.tap()
        search.typeText("School")
        let row = app.descendants(matching: .any)["custom-School"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "School never showed in the You tab")
    }
}
