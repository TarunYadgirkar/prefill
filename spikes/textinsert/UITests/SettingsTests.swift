import XCTest

@MainActor
final class SettingsTests: XCTestCase {
    func testOpenProviderSettingsFromApp() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["openSettings"].tap()
        XCTAssertTrue(Spike.settings.wait(for: .runningForeground, timeout: 10))
        Spike.snap("settings-from-helper", settle: 3)
        Spike.tree("settings-from-helper", Spike.settings)
    }

    func testEnableViaSettingsUI() {
        let s = Spike.settings
        s.terminate()
        s.launch()
        Spike.snap("settings-root", settle: 2)
        let general = s.staticTexts["General"]
        if !general.isHittable { s.swipeUp() }
        general.tap()
        let autofill = s.staticTexts["AutoFill & Passwords"]
        if !autofill.waitForExistence(timeout: 5) || !autofill.isHittable { s.swipeUp() }
        autofill.tap()
        Spike.snap("\(ProcessInfo.processInfo.environment["SPIKE_PREFIX"] ?? "x")-settings-autofill-passwords", settle: 2)
        Spike.tree("\(ProcessInfo.processInfo.environment["SPIKE_PREFIX"] ?? "x")-settings-autofill-passwords", s)
    }

    func testToggleProviderInSettings() {
        let p = ProcessInfo.processInfo.environment["SPIKE_PREFIX"] ?? "x"
        let s = Spike.settings
        s.terminate()
        s.launch()
        let general = s.staticTexts["General"]
        if !general.isHittable { s.swipeUp() }
        general.tap()
        let autofill = s.staticTexts["AutoFill & Passwords"]
        if !autofill.waitForExistence(timeout: 5) || !autofill.isHittable { s.swipeUp() }
        autofill.tap()
        let toggle = s.switches["AutoFillFromPrefill SpikeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        Spike.snap("\(p)-settings-before-toggle", settle: 1)
        toggle.switches.firstMatch.tap()
        Spike.both("\(p)-settings-after-toggle", s, settle: 2)
        Spike.tree("\(p)-settings-after-toggle-springboard", Spike.springboard)
        Spike.note("\(p)-settings-toggle", "toggle value after tap: \(String(describing: s.switches["AutoFillFromPrefill SpikeToggle"].value))")
    }

    func testToggleApplePasswordsSource() {
        let p = ProcessInfo.processInfo.environment["SPIKE_PREFIX"] ?? "x"
        let s = Spike.settings
        s.terminate()
        s.launch()
        let general = s.staticTexts["General"]
        if !general.isHittable { s.swipeUp() }
        general.tap()
        let autofill = s.staticTexts["AutoFill & Passwords"]
        if !autofill.waitForExistence(timeout: 5) || !autofill.isHittable { s.swipeUp() }
        autofill.tap()
        let toggle = s.switches["AutoFillFromPasswordsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        Spike.both("\(p)-settings-apple-passwords-toggled", s, settle: 2)
        Spike.note("\(p)-settings-apple-passwords", "apple passwords toggle=\(String(describing: s.switches["AutoFillFromPasswordsToggle"].value)) prefill toggle=\(String(describing: s.switches["AutoFillFromPrefill SpikeToggle"].value))")
    }
}
