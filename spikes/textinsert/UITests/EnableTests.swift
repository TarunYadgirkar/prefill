import XCTest

@MainActor
final class EnableTests: XCTestCase {
    var prefix: String { ProcessInfo.processInfo.environment["SPIKE_PREFIX"] ?? "x" }

    func testEnableViaHelper() {
        let app = XCUIApplication()
        app.launch()
        Spike.snap("\(prefix)-app-home")
        app.buttons["turnOn"].tap()
        Spike.snap("\(prefix)-helper-prompt", settle: 3)
        Spike.tree("\(prefix)-helper-prompt-app", app)
        Spike.tree("\(prefix)-helper-prompt-springboard", Spike.springboard)
        let labels = ["Turn On", "Allow", "Use", "Enable", "Continue", "OK"]
        let accept = Spike.firstButton(in: Spike.springboard, matching: labels)
        Spike.note("\(prefix)-helper", "accept button in springboard: \(accept?.label ?? "none"); status before accept: \(app.staticTexts["status"].label)")
        guard let accept else { return }
        accept.tap()
        Spike.snap("\(prefix)-helper-after-accept", settle: 3)
        Spike.note("\(prefix)-helper-result", "status after accept: \(app.staticTexts["status"].label)")
    }
}
