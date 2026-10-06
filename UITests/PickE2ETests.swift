import XCTest

// Click-and-pick in Safari, run by scripts/test.sh e2e after a host test has linked the
// Alex Rivera card: picking the second email in Prefill's list under the field puts it
// first in that list on the site from then on.
@MainActor
final class PickE2ETests: XCTestCase {
    private typealias Site = E2EServer.Site
    private let safari = SafariDriver.safari
    private let home = "alex.rivera@example.com"
    private let work = "alex@work.example.org"

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testAPickedEmailComesFirstOnTheSite() {
        XCUIApplication().launch()
        SafariDriver.enableExtension()
        let page = Site.siteA.page("application.html")
        SafariDriver.open(page, waitingFor: "First Name")
        Thread.sleep(forTimeInterval: 3)

        let pickedFirst = XCTContext.runActivity(named: "a. Pick the email that isn't first") { _ in
            SafariDriver.field("Email").tap()
            let wasFirst = listShows(work) && listShows(home)
                && row(work).frame.minY > row(home).frame.minY
            E2EServer.screenshot("pick-a-before")
            Thread.sleep(forTimeInterval: 1)
            row(work).tap()
            Thread.sleep(forTimeInterval: 1)
            XCTAssertEqual(SafariDriver.field("Email").value as? String, work)
            SafariDriver.dismissKeyboard()
            return wasFirst
        }
        XCTAssertTrue(pickedFirst, "the work email was already first, so the pick proves nothing")
        XCTContext.runActivity(named: "b. After a reload the picked email is first") { _ in
            SafariDriver.open(page, waitingFor: "First Name")
            Thread.sleep(forTimeInterval: 3)
            SafariDriver.field("Email").tap()
            XCTAssertTrue(listShows(work), "the email field offered no list")
            XCTAssertTrue(listShows(home), "the list lost the home email")
            E2EServer.screenshot("pick-b-after")
            XCTAssertLessThan(row(work).frame.minY, row(home).frame.minY, "the picked email isn't first")
            SafariDriver.dismissKeyboard()
        }
    }

    private func listShows(_ value: String) -> Bool {
        safari.webViews.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch.waitForExistence(timeout: 8)
    }

    // Prefill's own row. Safari's suggestion bubble shows the same emails just under the
    // field, over Prefill's first row, so of everything showing the value, the lowest one
    // above the keyboard is Prefill's.
    private func row(_ value: String) -> XCUIElement {
        let keyboard = safari.keyboards.firstMatch
        let top = keyboard.exists ? keyboard.frame.minY : .greatestFiniteMagnitude
        let matches = safari.webViews.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", value)).allElementsBoundByIndex
        let shown = matches.filter { $0.frame.maxY <= top }
        return shown.max { $0.frame.minY < $1.frame.minY } ?? matches.first ?? safari.webViews.firstMatch
    }
}
