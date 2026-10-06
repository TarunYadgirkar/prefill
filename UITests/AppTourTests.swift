import XCTest

// Walks onboarding and every screen on a simulator seeded by SeedHostTests, asking
// scripts/snap-server.py for a screenshot of each. scripts/ui-tour.sh runs it once per
// appearance; it is skipped in the plain e2e run, which has no seed and no snap server.
@MainActor
final class AppTourTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private let app = XCUIApplication()
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let tabBarTop: CGFloat = 0.88

    private var variant: String { env["PREFILL_VARIANT"] ?? "light" }

    override func setUpWithError() throws {
        try XCTSkipUnless(env["PREFILL_TOUR"] != nil, "needs scripts/ui-tour.sh")
        continueAfterFailure = false
    }

    func testTour() throws {
        setExtension(enabled: false)
        app.launch()
        walkOnboarding()
        walkCard()
        walkSites()
        walkInbox()
        walkSettings()
    }

    // A school email caught on a form waits in Recently added with School already picked.
    func testSchoolLabel() throws {
        try XCTSkipUnless(env["PREFILL_TOUR"] == "school")
        app.launch()
        tab("Inbox")
        let chip = element("suggested-label-alex.rivera@learn.example.edu")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue((chip.value as? String ?? "").hasPrefix("school"), "label is \(chip.value ?? "none")")
        snapAs("inbox-school-label")
    }

    // Records the bar while its values trade places, for frame-by-frame checking.
    func testBarMotion() throws {
        try XCTSkipUnless(env["PREFILL_TOUR"] == "motion")
        app.launch()
        let news = element("value-alex.news@example.com")
        let first = element("value-alex.rivera@example.com")
        XCTAssertTrue(news.waitForExistence(timeout: 10))
        call("/record/start?name=motion-reorder-\(variant)")
        pause(2)
        news.press(forDuration: 0.8, thenDragTo: first)
        pause(2)
        call("/record/stop")
        tab("Sites")
        let site = app.buttons["site-example.org"]
        swipeUp(until: site)
        site.tap()
        let school = app.buttons["site-value-alex.school@example.edu"]
        swipeUp(until: school)
        XCTAssertTrue(school.waitForExistence(timeout: 5))
        call("/record/start?name=motion-pin-\(variant)")
        pause(2)
        school.tap()
        pause(2)
        school.tap()
        pause(2)
        call("/record/stop")
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
        snap("onboarding-linked")
        swipeUp(until: next)
        next.tap()
        let later = app.buttons["sharing-next"]
        XCTAssertTrue(later.waitForExistence(timeout: 10))
        pause(1)
        snap("onboarding-sharing")
        later.tap()
        let open = app.buttons["open-safari-settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        snap("onboarding-safari")
        swipeUp(until: open)
        open.tap()
        flipAllowExtension(to: true)
        app.activate()
        let finish = app.buttons["finish-onboarding"]
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        snap("onboarding-safari-on")
        swipeUp(until: finish)
        finish.tap()
    }

    private func walkCard() {
        tab("Card")
        XCTAssertTrue(app.descendants(matching: .any)["quicktype-bar"].firstMatch.waitForExistence(timeout: 10))
        snap("card")
        let school = element("value-alex.school@example.edu")
        let home = element("value-alex.rivera@example.com")
        swipeUp(until: school)
        XCTAssertTrue(school.waitForExistence(timeout: 5))
        if school.isHittable && home.isHittable {
            school.press(forDuration: 0.8, thenDragTo: home)
            pause(2)
            snap("card-reordered")
        }
        let label = app.buttons["label-alex.school@example.edu"]
        swipeUp(until: label)
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        let custom = app.buttons["Custom label…"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        snap("card-label-menu")
        custom.tap()
        XCTAssertTrue(app.navigationBars["Custom label"].waitForExistence(timeout: 5))
        snap("card-relabel")
        app.buttons["Cancel"].tap()
        pickKind("Address")
        snap("card-address")
        swipeUp(until: app.buttons["add-value"])
        app.buttons["add-value"].tap()
        XCTAssertTrue(app.buttons["add-to-card"].waitForExistence(timeout: 5))
        pause(1)
        snap("card-add")
        app.buttons["Cancel"].tap()
        pickKind("Email")
    }

    private func walkSites() {
        tab("Sites")
        let site = app.buttons["site-example.org"]
        XCTAssertTrue(site.waitForExistence(timeout: 10))
        snap("sites")
        site.tap()
        XCTAssertTrue(app.navigationBars["example.org"].waitForExistence(timeout: 5))
        snap("site-detail")
        let school = app.buttons["site-value-alex.school@example.edu"]
        swipeUp(until: school)
        XCTAssertTrue(school.waitForExistence(timeout: 5))
        school.tap()
        pause(1)
        snap("site-pinned")
        app.navigationBars.buttons.firstMatch.tap()
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
        let remove = app.buttons.matching(identifier: "inbox-remove").firstMatch
        swipeUp(until: remove, above: tabBarTop)
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        pause(2)
        snapAs("inbox-after")
        // Everything not on the card can go back on it. Counting buttons needs every row on
        // screen, which only the default text size gives.
        guard variant != "large" else { return }
        let putBack = app.buttons.matching(identifier: "inbox-put-back")
        let removeButtons = app.buttons.matching(identifier: "inbox-remove")
        XCTAssertEqual(putBack.count, 2)
        let removable = removeButtons.count
        swipeUp(until: putBack.firstMatch, above: tabBarTop)
        putBack.firstMatch.tap()
        pause(2)
        XCTAssertEqual(removeButtons.count, removable + 1)
    }

    private func walkSettings() {
        tab("Settings")
        XCTAssertTrue(app.switches["match-each-site"].waitForExistence(timeout: 10))
        snap("settings")
        swipeUp(until: app.buttons["restore-card"])
        app.buttons["restore-card"].tap()
        pause(1)
        snap("settings-restore")
        let confirm = NSPredicate(format: "label == 'Restore original card' AND identifier != 'restore-card'")
        app.buttons.matching(confirm).firstMatch.tap()
        pause(2)
    }

    // MARK: - Helpers

    private func tab(_ title: String) {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        pause(1)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func pickKind(_ title: String) {
        app.segmentedControls["kind-picker"].buttons[title].tap()
        pause(1)
    }

    // Recent's rows are taller than a swipe at accessibility sizes, so it stops at anything
    // above the tab bar rather than risk scrolling the row out of the list.
    private func swipeUp(until element: XCUIElement, above limit: CGFloat = 0.8) {
        for _ in 0..<8 where !(element.exists && element.isHittable && element.frame.maxY < app.frame.height * limit) {
            app.swipeUp()
            pause(0.5)
        }
    }

    private func setExtension(enabled: Bool) {
        settings.terminate()
        settings.launch()
        flipAllowExtension(to: enabled)
        settings.terminate()
    }

    // SFSafariSettings opens Settings at its root in the simulator, so this walks from
    // wherever Settings is to Apps, Safari, Extensions, Prefill, the way a person would.
    private func flipAllowExtension(to enabled: Bool) {
        let toggle = settings.switches["Allow Extension"]
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        if !toggle.waitForExistence(timeout: 3) {
            openExtensionPage()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if (toggle.value as? String == "1") != enabled {
            toggle.switches.firstMatch.tap()
            pause(1)
        }
    }

    private func openExtensionPage() {
        for _ in 0..<5 where !settings.navigationBars["Settings"].exists {
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { break }
            back.tap()
            pause(1)
        }
        for label in ["Apps", "Safari", "Extensions", "Prefill"] {
            let cell = settings.staticTexts[label].firstMatch
            for _ in 0..<8 where !isComfortablyVisible(cell) {
                settings.swipeUp(velocity: .slow)
                pause(1)
            }
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "Settings has no \(label) row")
            cell.tap()
            pause(1.5)
        }
    }

    // On screen and clear of the floating search bar at the bottom.
    private func isComfortablyVisible(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && element.frame.maxY < settings.frame.height * 0.75
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func snap(_ screen: String) {
        pause(1)
        call("/snap?name=ui-\(screen)-\(variant)")
    }

    // The inbox and You screens keep their own names, like inbox-light.png.
    private func snapAs(_ screen: String) {
        pause(1)
        call("/snap?name=\(screen)-\(variant)")
    }

    private func call(_ path: String) {
        guard let url = URL(string: "http://127.0.0.1:\(env["PREFILL_SNAP_PORT"] ?? "8834")\(path)") else { return }
        _ = try? Data(contentsOf: url)
    }
}
