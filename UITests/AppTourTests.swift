import XCTest

// Walks onboarding and every screen on a simulator seeded by SeedHostTests, asking
// scripts/snap-server.py for a screenshot of each. scripts/ui-tour.sh runs it once per
// appearance; it is skipped in the plain e2e run, which has no seed and no snap server.
@MainActor
final class AppTourTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private let app = XCUIApplication()
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

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
        walkRecent()
        walkSettings()
    }

    // Records the bar while its values trade places, for frame-by-frame checking.
    func testBarMotion() throws {
        try XCTSkipUnless(env["PREFILL_TOUR"] == "motion")
        app.launch()
        tab("Sites")
        let site = app.buttons["site-example.org"]
        XCTAssertTrue(site.waitForExistence(timeout: 10))
        site.tap()
        let school = app.buttons["site-value-alex.school@example.edu"]
        XCTAssertTrue(school.waitForExistence(timeout: 5))
        call("/record/start?name=motion-pin")
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
        share.tap()
        let alex = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Alex Rivera'")).firstMatch
        XCTAssertTrue(alex.waitForExistence(timeout: 10))
        snap("onboarding-choose")
        alex.tap()
        let next = app.buttons["continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        snap("onboarding-linked")
        swipeUp(until: app.descendants(matching: .any)["quicktype-bar"].firstMatch)
        next.tap()
        let open = app.buttons["open-safari-settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        snap("onboarding-safari")
        open.tap()
        flipAllowExtension(to: true)
        app.activate()
        let finish = app.buttons["finish-onboarding"]
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        snap("onboarding-safari-on")
        finish.tap()
    }

    private func walkCard() {
        XCTAssertTrue(app.descendants(matching: .any)["quicktype-bar"].firstMatch.waitForExistence(timeout: 10))
        snap("card")
        let school = app.buttons["value-alex.school@example.edu"]
        let home = app.buttons["value-alex.rivera@example.com"]
        XCTAssertTrue(school.waitForExistence(timeout: 5))
        school.press(forDuration: 0.8, thenDragTo: home)
        pause(2)
        snap("card-reordered")
        app.buttons["value-alex.school@example.edu"].tap()
        XCTAssertTrue(app.navigationBars["Label"].waitForExistence(timeout: 5))
        snap("card-relabel")
        app.buttons["Cancel"].tap()
        pickKind("Address")
        snap("card-address")
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
        let school = app.buttons["site-value-alex.school@example.edu"]
        XCTAssertTrue(school.waitForExistence(timeout: 5))
        snap("site-detail")
        school.tap()
        pause(1)
        snap("site-pinned")
        app.navigationBars.buttons.firstMatch.tap()
    }

    private func walkRecent() {
        tab("Recently added")
        let waiting = app.buttons["Save to card"].firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 10))
        snap("recent")
        waiting.tap()
        pause(2)
        app.buttons["Dismiss"].firstMatch.tap()
        pause(1)
        let undo = app.buttons["Undo, take it off your card"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        pause(2)
        snap("recent-after")
    }

    private func walkSettings() {
        tab("Settings")
        XCTAssertTrue(app.switches["match-each-site"].waitForExistence(timeout: 10))
        snap("settings")
        swipeUp(until: app.buttons["restore-card"])
        app.buttons["restore-card"].tap()
        pause(1)
        snap("settings-restore")
        app.buttons["Restore original card"].tap()
        pause(2)
    }

    // MARK: - Helpers

    private func tab(_ title: String) {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        pause(1)
    }

    private func pickKind(_ title: String) {
        app.segmentedControls["kind-picker"].buttons[title].tap()
        pause(1)
    }

    private func swipeUp(until element: XCUIElement) {
        for _ in 0..<4 where !(element.exists && element.isHittable) {
            app.swipeUp()
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

    private func call(_ path: String) {
        guard let url = URL(string: "http://127.0.0.1:\(env["PREFILL_SNAP_PORT"] ?? "8834")\(path)") else { return }
        _ = try? Data(contentsOf: url)
    }
}
