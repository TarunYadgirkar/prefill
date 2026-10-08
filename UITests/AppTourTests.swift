import XCTest

// Walks onboarding and every screen on a simulator seeded by SeedHostTests, asking
// scripts/snap-server.py for a screenshot of each. scripts/ui-tour.sh runs it once per
// appearance; it is skipped in the plain e2e run, which has no seed and no snap server.
@MainActor
final class AppTourTests: XCTestCase {
    let env = ProcessInfo.processInfo.environment
    let app = XCUIApplication()
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    let tabBarTop: CGFloat = 0.88

    var variant: String { env["PREFILL_VARIANT"] ?? "light" }

    override func setUpWithError() throws {
        try XCTSkipUnless(env["PREFILL_TOUR"] != nil, "needs scripts/ui-tour.sh")
        continueAfterFailure = false
    }

    func testTour() throws {
        setExtension(enabled: false)
        app.launch()
        walkOnboarding()
        walkInbox()
        walkYou()
        walkSettings()
    }

    // A school email caught on a form waits in the inbox with School already picked.
    func testSchoolLabel() throws {
        try XCTSkipUnless(env["PREFILL_TOUR"] == "school")
        app.launch()
        tab("Inbox")
        let chip = element("suggested-label-alex.rivera@learn.example.edu")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue((chip.value as? String ?? "").hasPrefix("school"), "label is \(chip.value ?? "none")")
        snapAs("inbox-school-label")
    }

    // Records a reorder in the You tab, for frame-by-frame checking.
    func testBarMotion() throws {
        try XCTSkipUnless(env["PREFILL_TOUR"] == "motion")
        app.launch()
        tab("You")
        app.navigationBars.buttons["Edit"].tap()
        let news = element("value-alex.news@example.com")
        let first = element("value-alex.rivera@example.com")
        XCTAssertTrue(news.waitForExistence(timeout: 10))
        call("/record/start?name=motion-reorder-\(variant)")
        pause(2)
        news.press(forDuration: 0.8, thenDragTo: first)
        pause(2)
        call("/record/stop")
        app.navigationBars.buttons["Done"].tap()
    }

    private func walkOnboarding() {
        let share = app.buttons["share-card"]
        XCTAssertTrue(share.waitForExistence(timeout: 15))
        snap("onboarding-card")
        app.buttons["Work sign-in"].tap()
        pause(1)
        snap("onboarding-card-work")
        swipeUp(until: share)
        share.tap()
        let alex = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Alex Rivera'")).firstMatch
        XCTAssertTrue(app.navigationBars["Which card is yours?"].waitForExistence(timeout: 10))
        pause(1)
        snap("onboarding-choose")
        swipeUp(until: alex)
        XCTAssertTrue(alex.waitForExistence(timeout: 5))
        alex.tap()
        let next = app.buttons["continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(element("card-summary").exists)
        snap("onboarding-linked")
        swipeUp(until: next)
        next.tap()
        let later = app.buttons["sharing-next"]
        XCTAssertTrue(later.waitForExistence(timeout: 10))
        pause(1)
        snap("onboarding-sharing")
        later.tap()
        walkSafariStep()
    }

    // Step two, then the done screen.
    private func walkSafariStep() {
        let open = app.buttons["open-safari-settings"]
        let next = app.buttons["safari-next"]
        // Prefill reads Allow Extension from Safari, which can lag the switch the tour turned off,
        // so the step may already offer to continue.
        if !next.waitForExistence(timeout: 5) {
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            snap("onboarding-safari")
            swipeUp(until: open)
            open.tap()
            flipAllowExtension(to: true)
            app.activate()
        }
        // With two Prefill builds on the simulator, Settings may list the other one's extension;
        // the tour is about the app's screens, so it finishes setup later then.
        guard next.waitForExistence(timeout: 15) else {
            let later = app.buttons["finish-later"]
            swipeUp(until: later)
            later.tap()
            return
        }
        snap("onboarding-safari-on")
        swipeUp(until: next)
        next.tap()
        let finish = app.buttons["finish-onboarding"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        snap("onboarding-done")
        swipeUp(until: finish)
        finish.tap()
    }

    private func walkYou() {
        tab("You")
        let work = element("value-alex@work.example.org")
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        snapAs("you")
        work.tap()
        XCTAssertTrue(element("stored-place").waitForExistence(timeout: 5))
        snapAs("you-detail")
        let label = app.buttons["label-alex@work.example.org"]
        label.tap()
        let custom = app.buttons["Custom label…"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        snapAs("you-label-menu")
        custom.tap()
        XCTAssertTrue(app.navigationBars["Custom label"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["add-menu"].tap()
        let address = app.buttons["add-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        snapAs("you-add-menu")
        address.tap()
        XCTAssertTrue(app.buttons["add-to-card"].waitForExistence(timeout: 5))
        pause(1)
        snapAs("you-add")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Edit"].tap()
        snapAs("you-edit")
        app.navigationBars.buttons["Done"].tap()
        search(app, for: "work")
        snapAs("you-search")
        closeSearch(app)
    }

    private func walkInbox() {
        tab("Inbox")
        let add = app.buttons.matching(identifier: "inbox-add").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        snapAs("inbox")
        swipeUp(until: add, above: tabBarTop)
        add.tap()
        pause(2)
        let dismiss = app.buttons.matching(identifier: "inbox-dismiss").firstMatch
        swipeUp(until: dismiss, above: tabBarTop)
        dismiss.tap()
        pause(1)
        // A saved value leaves the inbox for its history on the You tab.
        XCTAssertFalse(app.buttons.matching(identifier: "inbox-remove").firstMatch.exists)
        snapAs("inbox-after")
    }

    private func walkSettings() {
        tab("Settings")
        XCTAssertTrue(app.switches["match-each-site"].waitForExistence(timeout: 10))
        snapAs("settings")
        openMutedSites()
        snap("muted-sites")
        app.navigationBars.buttons.firstMatch.tap()
        swipeUp(until: app.buttons["restore-card"])
        app.buttons["restore-card"].tap()
        pause(1)
        snapAs("settings-restore")
        let confirm = NSPredicate(format: "label == 'Restore original card' AND identifier != 'restore-card'")
        app.buttons.matching(confirm).firstMatch.tap()
        pause(2)
    }
}
