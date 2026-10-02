import XCTest

// Profile links end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=LinksE2ETests)
// after a host test has linked the Alex Rivera card: add a GitHub link, a website and a
// LinkedIn link in the app's Links tab, then focus a Greenhouse-style "GitHub/Portfolio:"
// field and read Safari's bar, which should offer both links in one option first.
@MainActor
final class LinksE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let links = ["github.com/alexrivera", "alexrivera.dev", "linkedin.com/in/alexrivera"]

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testGitHubPortfolioFieldOffersTheCardsLinks() {
        SafariDriver.enableExtension()
        app.launchArguments = ["-finishedOnboarding", "YES"]
        app.launch()
        links.forEach(addLink)
        E2EServer.screenshot("links-card")
        app.terminate()

        SafariDriver.open(E2EServer.Site.siteA.page("greenhouse.html"), waitingFor: "GitHub/Portfolio")
        Thread.sleep(forTimeInterval: 3)
        let combined = "github.com/alexrivera - alexrivera.dev"
        var slots: [String] = []
        for _ in 0..<4 {
            slots = SafariDriver.suggestions(focusing: "GitHub/Portfolio")
            if slots.first == combined { break }
            SafariDriver.dismissKeyboard()
            Thread.sleep(forTimeInterval: 2)
        }
        E2EServer.screenshot("links-greenhouse-bar")
        XCTAssertEqual(slots, [combined, "github.com/alexrivera", "alexrivera.dev"])
        SafariDriver.dismissKeyboard()
    }

    private func addLink(_ link: String) {
        let tab = app.tabBars.buttons["Card"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no Card tab")
        tab.tap()
        app.segmentedControls["kind-picker"].buttons["Links"].tap()
        // An empty list shows its own Add link button over the list's add row.
        let adds = app.buttons.matching(NSPredicate(format: "label == %@", "Add link"))
        XCTAssertTrue(adds.firstMatch.waitForExistence(timeout: 5), "no add button")
        let add = adds.allElementsBoundByIndex.first(where: \.isHittable) ?? adds.firstMatch
        add.tap()
        let field = app.textFields["link-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no link field")
        field.typeText(link)
        app.buttons["add-to-card"].tap()
        let row = app.descendants(matching: .any)["value-https://\(link)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(link) never showed on the card")
    }
}
