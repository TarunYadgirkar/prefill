import XCTest

extension AppTourTests {
    func tab(_ title: String) {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        pause(1)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    // Inbox rows are taller than a swipe at accessibility sizes, so it stops at anything
    // above the tab bar rather than risk scrolling the row out of the list.
    func swipeUp(until element: XCUIElement, above limit: CGFloat = 0.8) {
        for _ in 0..<8 where !(element.exists && element.isHittable && element.frame.maxY < app.frame.height * limit) {
            app.swipeUp()
            pause(0.5)
        }
    }

    func setExtension(enabled: Bool) {
        settings.terminate()
        settings.launch()
        flipAllowExtension(to: enabled)
        settings.terminate()
    }

    // SFSafariSettings opens Settings at its root in the simulator, so this walks from
    // wherever Settings is to Apps, Safari, Extensions, Prefill, the way a person would.
    func flipAllowExtension(to enabled: Bool) {
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

    func openExtensionPage() {
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
    func isComfortablyVisible(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && element.frame.maxY < settings.frame.height * 0.75
    }

    func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func snap(_ screen: String) {
        pause(1)
        call("/snap?name=ui-\(screen)-\(variant)")
    }

    // The inbox and You screens keep their own names, like inbox-light.png.
    func snapAs(_ screen: String) {
        pause(1)
        call("/snap?name=\(screen)-\(variant)")
    }

    func call(_ path: String) {
        guard let url = URL(string: "http://127.0.0.1:\(env["PREFILL_SNAP_PORT"] ?? "8834")\(path)") else { return }
        _ = try? Data(contentsOf: url)
    }

    func openSites() {
        tab("Settings")
        let sites = app.buttons["sites"]
        swipeUp(until: sites)
        sites.tap()
        pause(1)
    }
}
