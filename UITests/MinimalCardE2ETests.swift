import XCTest

// A minimal card end to end, run by scripts/test.sh e2e (PREFILL_E2E_ONLY=MinimalCardE2ETests)
// after a host test has linked the Alex Rivera card. The Inbox's one-time offer moves the
// emails, addresses and work phone to Prefill's contact, keeping the name and mobile number
// on the card Safari reads. Prefill's list under each field still offers every email, address
// part and phone number. Restore original card puts it all back.
@MainActor
final class MinimalCardE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let emails = ["alex.rivera@example.com", "alex@work.example.org", "alex.school@example.edu"]
    // Prefill's list captions a card value with its label (web/src/why.ts), as the seed card has them.
    private let emailCaptions = ["Home email", "Work email", "Email"]

    override func setUp() async throws {
        continueAfterFailure = false
        guard E2EServer.isRunning else {
            throw XCTSkip("Run through scripts/test.sh e2e, which starts the test sites.")
        }
    }

    func testPrefillsListOffersWhatAMinimalCardMovedOff() {
        SafariDriver.enableExtension()
        app.launchArguments = ["-finishedOnboarding", "YES"]
        app.launch()
        moveToMinimalCard()
        app.terminate()
        let card = E2EServer.card()
        XCTAssertEqual(card?.emails, [], "emails stayed on the card")
        XCTAssertEqual(card?.phones, ["+1 (510) 555-0134"], "the card should keep only the mobile number")
        XCTAssertEqual(card?.addressCount, 0, "addresses stayed on the card")

        let emailRows = zip(emails, emailCaptions).map { SafariDriver.Row(value: $0, detail: $1) }
        let greenhouse = list(on: "greenhouse.html", field: "Email", rows: emailRows, shot: "greenhouse-email")
        XCTAssertEqual(Set(greenhouse), Set(emails), "greenhouse email list was \(greenhouse)")
        let signup = list(on: "signup.html", field: "Email", rows: emailRows, shot: "signup-email")
        XCTAssertEqual(Set(signup), Set(emails), "signup email list was \(signup)")
        let checkout = list(on: "checkout.html", field: "Email", rows: emailRows, shot: "checkout-email")
        XCTAssertEqual(Set(checkout), Set(emails), "checkout email list was \(checkout)")
        let street = ["2400 Durant Ave", "1 Market St Suite 300"]
        XCTAssertEqual(listHere("Street address", rows: addressRows(street), shot: "checkout-street"), street)
        XCTAssertEqual(listHere("City", rows: addressRows(["Berkeley", "San Francisco"]), shot: "checkout-city"),
                       ["Berkeley", "San Francisco"])
        XCTAssertEqual(listHere("ZIP", rows: addressRows(["94704", "94105"]), shot: "checkout-zip"), ["94704", "94105"])
        let phones = [
            SafariDriver.Row(value: "+1 (510) 555-0134", detail: "Mobile phone"),
            SafariDriver.Row(value: "+1 (415) 555-0199", detail: "Work phone")
        ]
        let phone = listHere("Phone", rows: phones, shot: "checkout-phone")
        XCTAssertEqual(phone.first, "+1 (510) 555-0134", "phone list was \(phone)")

        restoreOriginalCard()
        XCTAssertEqual(E2EServer.waitForCard { $0.emails.count == 3 }?.emails, emails, "restore left emails off")
        XCTAssertEqual(E2EServer.card()?.addressCount, 2, "restore left addresses off")
    }

    // The seed card's first address is home, the second work.
    private func addressRows(_ values: [String]) -> [SafariDriver.Row] {
        zip(values, ["Home address", "Work address"]).map { SafariDriver.Row(value: $0, detail: $1) }
    }

    // Opens the page and reads which of `rows` Prefill's list under the field shows.
    private func list(on page: String, field: String, rows: [SafariDriver.Row], shot: String) -> [String] {
        SafariDriver.open(E2EServer.Site.siteA.page(page), waitingFor: field)
        Thread.sleep(forTimeInterval: 3)
        return listHere(field, rows: rows, shot: shot)
    }

    private func listHere(_ field: String, rows: [SafariDriver.Row], shot: String) -> [String] {
        let shown = SafariDriver.prefillList(focusing: field, rows: rows)
        E2EServer.screenshot("minimal-card-\(shot)")
        SafariDriver.dismissKeyboard()
        return shown
    }

    // The Inbox lists exactly what moves; the one button under that list is the confirmation.
    private func moveToMinimalCard() {
        app.tabBars.buttons["Inbox"].firstMatch.tap()
        let keep = app.buttons["short-card-keep"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 10), "no offer to keep the card short")
        for _ in 0..<8 where !keep.isHittable { app.swipeUp() }
        E2EServer.screenshot("minimal-card-offer")
        keep.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["short-card-offer"].waitForNonExistence(timeout: 10),
            "the offer stayed after the move"
        )
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
