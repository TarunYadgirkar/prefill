import XCTest

// Sent applications end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=ApplicationsE2ETests)
// after a host test has linked the Alex Rivera card: apply on the Greenhouse-style page in
// Safari, then open You, History, Applications in the app and read the answers it kept.
@MainActor
final class ApplicationsE2ETests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testASentApplicationShowsInTheApp() {
        SafariDriver.enableExtension()
        SafariDriver.open(E2EServer.Site.siteA.page("greenhouse.html"), waitingFor: "School")
        Thread.sleep(forTimeInterval: 3)
        SafariDriver.type("Alex", into: "First Name")
        SafariDriver.type("Rivera", into: "Last Name")
        SafariDriver.type("Cal Poly", into: "School")
        SafariDriver.type("A friend at the career fair", into: "How did you hear")
        E2EServer.screenshot("application-filled")
        SafariDriver.tapButton("Submit application")
        XCTAssertTrue(SafariDriver.waitForText("all set"), "the application never reached the thanks page")
        Thread.sleep(forTimeInterval: 2)

        app.launchArguments = ["-finishedOnboarding", "YES"]
        app.launch()
        let tab = app.tabBars.buttons["You"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no You tab")
        tab.tap()
        let row = app.descendants(matching: .any)["applications"].firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Applications row in the You tab")
        row.tap()
        let title = app.staticTexts["Apply for Software Engineer"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the application isn't in the list")
        E2EServer.screenshot("application-list")
        title.tap()
        XCTAssertTrue(app.staticTexts["Cal Poly"].waitForExistence(timeout: 5), "the School answer is missing")
        XCTAssertTrue(app.staticTexts["A friend at the career fair"].exists, "the free-text answer is missing")
        E2EServer.screenshot("application-detail")
    }
}
