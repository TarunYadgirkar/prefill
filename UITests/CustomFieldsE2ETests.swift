import XCTest

// Custom fields end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=CustomFieldsE2ETests)
// after a host test has linked the Alex Rivera card: add "School" = "UC Berkeley" in the
// app's Custom tab, then focus the Greenhouse-style "School" field and read Safari's bar.
@MainActor
final class CustomFieldsE2ETests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testSchoolFieldOffersTheCustomAnswer() {
        SafariDriver.enableExtension()
        app.launchArguments = ["-finishedOnboarding", "YES"]
        app.launch()
        addSchool()
        E2EServer.screenshot("custom-card")
        app.terminate()

        SafariDriver.open(E2EServer.Site.siteA.page("greenhouse.html"), waitingFor: "School")
        Thread.sleep(forTimeInterval: 3)
        var slots: [String] = []
        for _ in 0..<4 {
            slots = SafariDriver.suggestions(focusing: "School")
            if slots.first == "UC Berkeley" { break }
            SafariDriver.dismissKeyboard()
            Thread.sleep(forTimeInterval: 2)
        }
        E2EServer.screenshot("custom-field-bar")
        XCTAssertEqual(slots.first, "UC Berkeley")
        SafariDriver.dismissKeyboard()
    }

    private func addSchool() {
        let tab = app.tabBars.buttons["Card"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no Card tab")
        tab.tap()
        app.segmentedControls["kind-picker"].buttons["Custom"].tap()
        let adds = app.buttons.matching(NSPredicate(format: "label == %@", "Add field"))
        XCTAssertTrue(adds.firstMatch.waitForExistence(timeout: 5), "no add button")
        let add = adds.allElementsBoundByIndex.first(where: \.isHittable) ?? adds.firstMatch
        add.tap()
        let label = app.textFields["custom-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "no label field")
        label.typeText("School")
        app.textFields["custom-value"].tap()
        app.textFields["custom-value"].typeText("UC Berkeley")
        app.buttons["save-custom-field"].tap()
        let row = app.descendants(matching: .any)["custom-School"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "School never showed on the card")
    }
}
