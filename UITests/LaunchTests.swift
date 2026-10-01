import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesToRootView() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["root"].waitForExistence(timeout: 10))
    }
}
