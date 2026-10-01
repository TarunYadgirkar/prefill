import XCTest

// The Safari extension end to end, run by scripts/test.sh e2e after a host test has linked
// the Alex Rivera card (emails home alex.rivera@, work alex@work., unlabeled school).
// Site A is localhost and site B is 127.0.0.1, both served by scripts/e2e-server.py.
@MainActor
final class ExtensionE2ETests: XCTestCase {
    private typealias Site = E2EServer.Site
    private let newEmail = "new.person@example.org"
    private let workEmail = "alex@work.example.org"

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testTheCardFollowsEachSite() {
        XCUIApplication().launch()
        SafariDriver.enableExtension()

        XCTContext.runActivity(named: "a. A new email from a sign-up on site A goes onto the card") { _ in
            signUp(on: .siteA, email: newEmail, shot: "a-signup-site-a")
            let card = E2EServer.waitForCard { $0.emails.contains(newEmail) }
            XCTAssertEqual(card?.emails.first, newEmail, "card emails: \(card?.emails ?? [])")
        }
        XCTContext.runActivity(named: "b. Site A offers the new email first") { _ in
            expectFirstSuggestion(newEmail, on: .siteA, shot: "b-site-a-bar")
        }
        XCTContext.runActivity(named: "c. Site B offers the work email used there, site A keeps its own") { _ in
            signUp(on: .siteB, email: workEmail, shot: "c-signup-site-b")
            expectFirstSuggestion(workEmail, on: .siteB, shot: "c-site-b-bar")
            expectFirstSuggestion(newEmail, on: .siteA, shot: "c-site-a-bar-again")
        }
        XCTContext.runActivity(named: "d. A gift for someone else leaves the card alone") { _ in
            let before = E2EServer.card()
            sendGift(on: .siteA)
            Thread.sleep(forTimeInterval: 5)
            let after = E2EServer.card()
            XCTAssertNotNil(before)
            XCTAssertEqual(before?.emails.sorted(), after?.emails.sorted())
            XCTAssertEqual(before?.phones.sorted(), after?.phones.sorted())
            XCTAssertEqual(before?.addressCount, after?.addressCount)
        }
    }

    private func signUp(on site: Site, email: String, shot: String) {
        SafariDriver.open(site.page("signup.html"), waitingFor: "Email")
        SafariDriver.type("Alex Rivera", into: "Full name")
        SafariDriver.type(email, into: "Email")
        E2EServer.screenshot(shot)
        SafariDriver.tapButton("Create account")
        XCTAssertTrue(SafariDriver.waitForText("all set"), "the sign-up never reached the thanks page")
    }

    private func sendGift(on site: Site) {
        SafariDriver.open(site.page("gift.html"), waitingFor: "Recipient")
        SafariDriver.type("Jordan Lee", into: "Recipient's name")
        SafariDriver.type("jordan.lee@example.net", into: "Recipient's email")
        SafariDriver.type("77 Gift Way", into: "Street address")
        SafariDriver.type("Oakland", into: "City")
        SafariDriver.type("94612", into: "ZIP")
        E2EServer.screenshot("d-gift-site-a")
        SafariDriver.tapButton("Send gift")
        XCTAssertTrue(SafariDriver.waitForText("all set"), "the gift form never reached the thanks page")
    }

    // The card is rewritten from the page's load message, which can land just after the
    // first focus on a cold extension process, so focus again a few times before failing.
    // The page has no password field: with one, Safari offers passwords instead of contacts.
    private func expectFirstSuggestion(_ expected: String, on site: Site, shot: String) {
        SafariDriver.open(site.page("contact.html"), waitingFor: "Email")
        Thread.sleep(forTimeInterval: 3)
        var slots: [String] = []
        for _ in 0..<4 {
            slots = SafariDriver.suggestions(focusing: "Email")
            if slots.first?.hasSuffix(expected) == true { break }
            SafariDriver.dismissKeyboard()
            Thread.sleep(forTimeInterval: 2.5)
        }
        E2EServer.screenshot(shot)
        XCTAssertTrue(slots.first?.hasSuffix(expected) == true, "QuickType bar on \(site.rawValue): \(slots)")
        SafariDriver.dismissKeyboard()
    }
}
