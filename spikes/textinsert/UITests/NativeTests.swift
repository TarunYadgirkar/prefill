import XCTest

@MainActor
final class NativeTests: XCTestCase {
    var prefix: String { ProcessInfo.processInfo.environment["SPIKE_PREFIX"] ?? "x" }

    func menuSummary(_ app: XCUIApplication) -> String {
        "app=\(app.menuItems.allElementsBoundByIndex.map(\.label))"
    }

    func testNativeFieldMenu() {
        var lines: [String] = []
        let app = XCUIApplication()
        app.launch()
        app.buttons["nativeFields"].tap()
        let f = app.textFields["Email"]
        XCTAssertTrue(f.waitForExistence(timeout: 5))
        f.tap()
        Spike.both("\(prefix)-native-focused", app)
        Thread.sleep(forTimeInterval: 1)
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        _ = app.menuItems.firstMatch.waitForExistence(timeout: 3)
        Spike.both("\(prefix)-native-edit-menu", app)
        lines.append("native edit menu: \(menuSummary(app))")
        let autofill = app.menuItems["AutoFill"]
        if autofill.exists {
            autofill.tap()
            Spike.snap("\(prefix)-native-autofill-t03", settle: 0.3)
            Spike.both("\(prefix)-native-autofill-submenu", app, settle: 1.5)
            lines.append("native autofill submenu: \(menuSummary(app))")
            if app.menuItems["Passwords"].exists {
                app.menuItems["Passwords"].tap()
                Spike.both("\(prefix)-native-passwords-pane", app, settle: 2)
                lines.append("native after Passwords: \(menuSummary(app))")
            }
        }
        Spike.note("\(prefix)-native", lines.joined(separator: "\n"))
    }

    func testNativeInsertFlow() {
        var lines: [String] = []
        var taps = 0
        let app = XCUIApplication()
        app.launch()
        app.buttons["nativeFields"].tap()
        let f = app.textFields["Email"]
        XCTAssertTrue(f.waitForExistence(timeout: 5))
        f.tap(); taps += 1
        Thread.sleep(forTimeInterval: 1)
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap(); taps += 1
        XCTAssertTrue(app.menuItems["AutoFill"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1)
        app.menuItems["AutoFill"].tap(); taps += 1
        let pw = app.buttons["Passwords"]
        XCTAssertTrue(pw.waitForExistence(timeout: 3))
        Spike.both("\(prefix)-native-ins-2-submenu", app, settle: 0.5)
        pw.tap(); taps += 1
        let chooser = Spike.hittable(app, "Prefill Spike")
        if chooser.waitForExistence(timeout: 5) {
            Spike.both("\(prefix)-native-ins-3-chooser", app, settle: 0.5)
            chooser.tap(); taps += 1
        } else {
            lines.append("no chooser")
        }
        let target = app.buttons["ti-two@example.net"]
        let appeared = target.waitForExistence(timeout: 10)
        Spike.both("\(prefix)-native-ins-4-provider-ui", app, settle: 1)
        lines.append("provider value visible: \(appeared)")
        if appeared {
            target.tap(); taps += 1
            Spike.both("\(prefix)-native-ins-5-after-insert", app, settle: 2)
            lines.append("field value after insert: \(String(describing: app.textFields["Email"].value))")
            lines.append("taps: \(taps)")
        }
        Spike.note("\(prefix)-native-ins", lines.joined(separator: "\n"))
    }

    func testNativeContactBaseline() {
        var lines: [String] = []
        let app = XCUIApplication()
        app.launch()
        app.buttons["nativeFields"].tap()
        let f = app.textFields["Email"]
        XCTAssertTrue(f.waitForExistence(timeout: 5))
        f.tap()
        Thread.sleep(forTimeInterval: 1)
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.menuItems["AutoFill"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1)
        app.menuItems["AutoFill"].tap()
        let contact = app.buttons["Contact"]
        XCTAssertTrue(contact.waitForExistence(timeout: 3))
        contact.tap()
        Spike.both("\(prefix)-native-contact-1-after-contact", app, settle: 2)
        Spike.tree("\(prefix)-native-contact-1-springboard", Spike.springboard)
        let alex = app.staticTexts["Alex Rivera"]
        if alex.waitForExistence(timeout: 3) {
            alex.tap()
            Spike.both("\(prefix)-native-contact-2-card", app, settle: 2)
            let work = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "alex@work.example.org")).firstMatch
            if work.waitForExistence(timeout: 3) {
                work.tap()
                Spike.both("\(prefix)-native-contact-3-after-pick", app, settle: 2)
                lines.append("field value after contact pick: \(String(describing: app.textFields["Email"].value))")
            } else { lines.append("work email not found on card") }
        } else { lines.append("Alex Rivera not found") }
        Spike.note("\(prefix)-native-contact", lines.joined(separator: "\n"))
    }
}
