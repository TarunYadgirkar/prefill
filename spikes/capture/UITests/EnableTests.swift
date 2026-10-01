import XCTest

@MainActor
final class EnableTests: XCTestCase {
    private func reveal(_ el: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if el.exists && el.isHittable && el.frame.maxY < app.frame.height * 0.75 { return }
            app.swipeUp(velocity: .slow)
        }
    }

    private func openSafariExtensions() -> XCUIApplication {
        let s = Driver.settings
        s.terminate()
        s.launch()
        let apps = s.staticTexts["Apps"]
        reveal(apps, in: s)
        apps.tap()
        Driver.both("settings-apps", s)
        let safari = s.staticTexts["Safari"]
        reveal(safari, in: s)
        safari.tap()
        Driver.both("settings-safari", s)
        let ext = s.staticTexts["Extensions"]
        reveal(ext, in: s)
        ext.tap()
        Driver.both("settings-extensions", s)
        return s
    }

    func testExploreSettings() {
        let s = openSafariExtensions()
        let mine = s.staticTexts["Prefill Capture"]
        if mine.waitForExistence(timeout: 5) {
            mine.tap()
            Driver.both("settings-extension-detail", s)
        }
    }

    func testEnableExtension() {
        let s = openSafariExtensions()
        let mine = s.staticTexts["Prefill Capture"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        mine.tap()
        Driver.both("enable-1-detail-before", s)
        let toggle = s.switches["Allow Extension"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let before = "\(String(describing: toggle.value))"
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.tap() }
        Driver.both("enable-2-detail-after-toggle", s)
        Driver.note("enable-switch", "before=\(before) after=\(String(describing: s.switches["Allow Extension"].value))")
    }
}
