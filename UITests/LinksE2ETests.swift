import XCTest

// Profile links end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=LinksE2ETests)
// after a host test has linked the Alex Rivera card: add a GitHub link, a website and a
// LinkedIn link in the app's Links tab, then focus a Greenhouse-style "GitHub/Portfolio:"
// field and read Safari's bar, which should offer both links in one option first. On the way,
// Settings > Sharing your card moves the links off the card Safari and NameDrop read onto
// Prefill's own contact, and the bar still offers the links and the card's emails.
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
        XCTAssertEqual(E2EServer.card()?.linkCount, links.count, "links never reached the card")
        moveLinksOffCard()
        app.terminate()
        XCTAssertEqual(E2EServer.card()?.linkCount, 0, "links stayed on the card")

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

        let emails = SafariDriver.suggestions(focusing: "Email")
        E2EServer.screenshot("links-greenhouse-email-bar")
        XCTAssertTrue(emails.contains { $0.contains("alex.rivera@example.com") }, "email bar was \(emails)")
        SafariDriver.dismissKeyboard()
    }

    private func moveLinksOffCard() {
        app.tabBars.buttons["Settings"].tap()
        let row = app.buttons["sharing-your-card"].firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let move = app.buttons["move-off-card"].firstMatch
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10), "no list of values on the card")
        keepOnlyLinksChosen()
        for _ in 0..<8 where !(move.exists && move.isHittable) { app.swipeUp() }
        XCTAssertTrue(move.waitForExistence(timeout: 5), "no Move button")
        E2EServer.screenshot("links-sharing")
        move.tap()
        let confirm = app.buttons["Move off your card"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation")
        confirm.tap()
        let links = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH 'extra-link-'"))
        XCTAssertTrue(links.firstMatch.waitForNonExistence(timeout: 10), "links stayed in the list")
        E2EServer.screenshot("links-sharing-clean")
    }

    // The list also offers emails, phones and addresses; this test moves links alone.
    private func keepOnlyLinksChosen() {
        let format = "identifier BEGINSWITH 'extra-' AND NOT identifier BEGINSWITH 'extra-link-'"
        for toggle in app.switches.matching(NSPredicate(format: format)).allElementsBoundByIndex {
            for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
            guard toggle.value as? String == "1" else { continue }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
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
