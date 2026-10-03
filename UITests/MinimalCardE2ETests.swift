import XCTest

// A minimal card end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=MinimalCardE2ETests)
// after a host test has linked the Alex Rivera card. Settings > Sharing your card moves the
// emails, addresses and work phone to Prefill's contact, keeping the name and mobile number
// on the card Safari reads. Safari's bar then offers the emails and address parts from
// Prefill's datalist and the mobile number from the card. Restore original card puts it all back.
@MainActor
final class MinimalCardE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let emails = ["alex.rivera@example.com", "alex@work.example.org", "alex.school@example.edu"]

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testSafarisBarOffersWhatAMinimalCardMovedOff() {
        SafariDriver.enableExtension()
        app.launchArguments = ["-finishedOnboarding", "YES"]
        app.launch()
        moveToMinimalCard()
        app.terminate()
        let card = E2EServer.card()
        XCTAssertEqual(card?.emails, [], "emails stayed on the card")
        XCTAssertEqual(card?.phones, ["+1 (510) 555-0134"], "the card should keep only the mobile number")
        XCTAssertEqual(card?.addressCount, 0, "addresses stayed on the card")

        let greenhouse = bar(on: "greenhouse.html", field: "Email", shot: "greenhouse-email")
        XCTAssertTrue(greenhouse.contains(emails[0]) && greenhouse.count > 1, "greenhouse email bar was \(greenhouse)")
        // A sign-up form's email field gets Safari's Passwords key in the bar instead, so there
        // Prefill's emails show in WebKit's list under the field.
        let signup = bar(on: "signup.html", field: "Email", shot: "signup-email", keepFocus: true)
        let listed = SafariDriver.safari.descendants(matching: .any)[emails[0]].firstMatch.exists
        XCTAssertTrue(signup.contains(emails[0]) || listed, "signup email bar was \(signup), no list")
        SafariDriver.dismissKeyboard()
        let checkout = bar(on: "checkout.html", field: "Email", shot: "checkout-email")
        XCTAssertTrue(checkout.contains(emails[0]), "checkout email bar was \(checkout)")
        XCTAssertEqual(barHere("Street address", shot: "checkout-street"), ["2400 Durant Ave", "1 Market St Suite 300"])
        XCTAssertEqual(barHere("City", shot: "checkout-city"), ["Berkeley", "San Francisco"])
        XCTAssertEqual(barHere("ZIP", shot: "checkout-zip"), ["94704", "94105"])
        let phone = barHere("Phone", shot: "checkout-phone")
        XCTAssertTrue(phone.first?.contains("(510) 555-0134") == true, "phone bar was \(phone)")

        restoreOriginalCard()
        XCTAssertEqual(E2EServer.waitForCard { $0.emails.count == 3 }?.emails, emails, "restore left emails off")
        XCTAssertEqual(E2EServer.card()?.addressCount, 2, "restore left addresses off")
    }

    // Opens the page and reads the field's bar, retrying while the app answers.
    private func bar(on page: String, field: String, shot: String, keepFocus: Bool = false) -> [String] {
        SafariDriver.open(E2EServer.Site.siteA.page(page), waitingFor: field)
        Thread.sleep(forTimeInterval: 3)
        return barHere(field, shot: shot, keepFocus: keepFocus)
    }

    private func barHere(_ field: String, shot: String, keepFocus: Bool = false) -> [String] {
        var slots: [String] = []
        for _ in 0..<4 {
            slots = SafariDriver.suggestions(focusing: field)
            if !slots.isEmpty, !slots.contains("I") { break }
            SafariDriver.dismissKeyboard()
            Thread.sleep(forTimeInterval: 2)
        }
        E2EServer.screenshot("minimal-card-\(shot)")
        if !keepFocus { SafariDriver.dismissKeyboard() }
        return slots
    }

    private func moveToMinimalCard() {
        app.tabBars.buttons["Settings"].firstMatch.tap()
        let row = app.buttons["sharing-your-card"].firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let move = app.buttons["move-off-card"].firstMatch
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10), "no list of values on the card")
        for _ in 0..<8 where !(move.exists && move.isHittable) { app.swipeUp() }
        XCTAssertTrue(move.waitForExistence(timeout: 5), "no Move button")
        E2EServer.screenshot("minimal-card-sharing")
        move.tap()
        let confirm = app.buttons["Move off your card"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation")
        E2EServer.screenshot("minimal-card-confirm")
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["card-is-clean"].waitForExistence(timeout: 10))
        E2EServer.screenshot("minimal-card-sharing-done")
    }

    private func restoreOriginalCard() {
        app.launch()
        app.tabBars.buttons["Settings"].firstMatch.tap()
        let restore = app.buttons["restore-card"].firstMatch
        for _ in 0..<6 where !restore.isHittable { app.swipeUp() }
        restore.tap()
        let dialog = app.buttons.matching(NSPredicate(format: "label == %@", "Restore original card"))
        let deadline = Date().addingTimeInterval(5)
        while dialog.count < 2, Date() < deadline { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(dialog.count, 2, "no restore confirmation")
        let confirm = dialog.allElementsBoundByIndex.first { $0.identifier != "restore-card" } ?? restore
        E2EServer.screenshot("minimal-card-restore")
        confirm.tap()
        _ = E2EServer.waitForCard { $0.emails.count == 3 && $0.addressCount == 2 }
        app.terminate()
    }
}
