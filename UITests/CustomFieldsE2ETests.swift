import XCTest

// Custom fields end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=CustomFieldsE2ETests)
// after a host test has linked the Alex Rivera card: add the student starter set, with its school
// already filled in, in the app's Custom tab, then focus the Greenhouse-style "School" field and read Prefill's
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
        app.launchArguments = ["-finishedOnboarding", "YES", "-studentStarterDone", "NO"]
        app.launch()
        addSchool()
        E2EServer.screenshot("custom-card")
        app.terminate()

        SafariDriver.open(E2EServer.Site.siteA.page("greenhouse.html"), waitingFor: "School")
        Thread.sleep(forTimeInterval: 3)
        let listed = SafariDriver.prefillList(
            focusing: "School", rows: [SafariDriver.Row(value: berkeley, detail: "School")]
        )
        E2EServer.screenshot("custom-field-list")
        XCTAssertEqual(listed.first, berkeley)
        SafariDriver.dismissKeyboard()
    }

    private func addSchool() {
        let tab = app.tabBars.buttons["Card"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no Card tab")
        tab.tap()
        app.segmentedControls["kind-picker"].buttons["Custom"].tap()
        let starters = app.buttons.matching(identifier: "add-student-answers")
        XCTAssertTrue(starters.firstMatch.waitForExistence(timeout: 5), "no student answers button")
        (starters.allElementsBoundByIndex.first(where: \.isHittable) ?? starters.firstMatch).tap()
        let school = app.textFields["student-school"]
        XCTAssertTrue(school.waitForExistence(timeout: 5), "no school answer")
        XCTAssertEqual(school.value as? String, berkeley)
        E2EServer.screenshot("custom-student-answers")
        app.buttons["save-student-answers"].tap()
        let row = app.descendants(matching: .any)["custom-School"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "School never showed on the card")
    }
}
