import XCTest

@MainActor
final class CaptureTests: XCTestCase {
    private var s: XCUIApplication { Driver.safari }

    func testPermissionExplore() {
        Driver.open("away.html")
        Driver.both("perm-1-page-ask", s)
        let candidates = s.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Page' OR label CONTAINS[c] 'Extension' OR identifier CONTAINS[c] 'Extension' OR label CONTAINS[c] 'Menu'"))
        Driver.note("perm-buttons", candidates.allElementsBoundByIndex.map { "\($0.identifier) | \($0.label)" }.joined(separator: "\n"))
        s.buttons["MoreMenuButton"].tap()
        Driver.both("perm-2-page-menu", s)
        let ext = s.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Prefill Capture'")).firstMatch
        if ext.waitForExistence(timeout: 3) {
            ext.tap()
            Driver.both("perm-3-extension-item", s)
        }
    }
}

@MainActor
final class FormTests: XCTestCase {
    private var s: XCUIApplication { Driver.safari }
    private var tag: String { ProcessInfo.processInfo.environment["TAG"] ?? "t" }

    override func setUp() {
        continueAfterFailure = true
    }

    private func finish(_ name: String) {
        Driver.note("\(tag)-\(name)-badge", Driver.badge(timeout: 6))
        Driver.both("\(tag)-\(name)-after", s)
    }

    func testFormButton() {
        Driver.open("form-button.html")
        Driver.type("Jordan Button", into: "Full name")
        Driver.type("button.\(tag)@newmail.example", into: "Email")
        Driver.type("5105550111", into: "Phone")
        Driver.type("77 Button Way", into: "Street address")
        Driver.type("123456", into: "Code")
        Driver.type("hunter2-test", into: "Password")
        Driver.snap("\(tag)-button-filled")
        for label in ["Close", "Not Now", "Choose My Own Password", "Other Options…"] {
            let b = s.buttons[label]
            if b.exists { b.tap(); break }
        }
        Driver.both("\(tag)-button-before-submit", s)
        s.webViews.buttons["Create account"].tap()
        finish("button")
    }

    func testFormReturn() {
        Driver.open("form-return.html")
        Driver.type("Jordan Return", into: "Your name")
        Driver.type("return.\(tag)@newmail.example", into: "Your e-mail")
        Driver.snap("\(tag)-return-filled")
        let mail = Driver.field("Your e-mail")
        mail.tap()
        Thread.sleep(forTimeInterval: 0.8)
        mail.typeText("\n")
        finish("return")
    }

    func testFormFetch() {
        Driver.open("form-fetch.html")
        Driver.type("fetch.\(tag)@newmail.example", into: "Email")
        Driver.type("5105550122", into: "Phone")
        Driver.snap("\(tag)-fetch-filled")
        s.webViews.buttons["Join waitlist"].tap()
        let done = s.webViews.staticTexts["You are on the list"]
        Driver.note("\(tag)-fetch-status", done.waitForExistence(timeout: 5) ? "status shown" : "status missing")
        finish("fetch")
        s.webViews.links["Continue to the next page"].tap()
        Driver.both("\(tag)-fetch-navigated-away", s, settle: 3)
    }

    func testLatency() {
        Driver.open("form-latency.html")
        var lines: [String] = []
        for i in 1...6 {
            let f = Driver.field("Email")
            f.tap()
            Thread.sleep(forTimeInterval: 0.5)
            f.typeText("lat\(i).\(tag)@newmail.example")
            Driver.dismissKeyboard()
            s.webViews.buttons["Save"].tap()
            Thread.sleep(forTimeInterval: 2.5)
            lines.append("\(i): \(Driver.badge(timeout: 4))")
            Driver.safari.webViews.buttons["Clear"].tap()
        }
        Driver.note("\(tag)-latency-badges", lines.joined(separator: "\n"))
        Driver.both("\(tag)-latency-after", s)
    }
}

@MainActor
final class GrantTests: XCTestCase {
    func testGrantAlways() {
        let s = Driver.safari
        Driver.open("form-button.html")
        Driver.both("grant-0-page-before", s)
        s.buttons["MoreMenuButton"].tap()
        Driver.both("grant-1-page-menu", s)
        s.buttons["Prefill Capture"].tap()
        Driver.both("grant-2-site-prompt", s)
        s.buttons["Always Allow…"].tap()
        Driver.both("grant-3-always-options", s)
        let every = s.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Every Website'")).firstMatch
        let this = s.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'This Website'")).firstMatch
        if every.waitForExistence(timeout: 3) { every.tap() } else if this.exists { this.tap() }
        Driver.both("grant-4-after", s)
        s.buttons["MoreMenuButton"].tap()
        Driver.both("grant-5-page-menu-after", s)
    }
}

@MainActor
final class ProbeTests: XCTestCase {
    func testProbe() {
        let tag = ProcessInfo.processInfo.environment["TAG"] ?? "p"
        let s = Driver.safari
        Driver.open("form-latency.html?probe=1")
        Driver.type("probe.\(tag)@newmail.example", into: "Email")
        s.webViews.buttons["Save"].tap()
        var seen = "no alert"
        for i in 0..<10 {
            let a = Driver.springboard.alerts.firstMatch
            let b = s.alerts.firstMatch
            if a.exists || b.exists {
                let alert = a.exists ? a : b
                seen = "alert after ~\(i)s in \(a.exists ? "springboard" : "safari"): \(alert.label) buttons=\(alert.buttons.allElementsBoundByIndex.map(\.label))"
                Driver.snap("\(tag)-probe-alert", settle: 0.5)
                Driver.tree("\(tag)-probe-alert-springboard", Driver.springboard)
                if ProcessInfo.processInfo.environment["ALERT"] == "continue" {
                    alert.buttons["Continue"].tap()
                    for step in 1...4 {
                        Driver.snap("\(tag)-probe-continue-\(step)", settle: 1.5)
                        Driver.tree("\(tag)-probe-continue-\(step)-springboard", Driver.springboard)
                        let next = Driver.springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Full Access", "Allow"])).firstMatch
                        if next.exists { next.tap() } else { break }
                    }
                } else {
                    let deny = alert.buttons["Don’t Allow"]
                    if deny.exists { deny.tap() }
                }
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        Driver.note("\(tag)-probe-alert-result", seen)
        Driver.note("\(tag)-probe-badge", Driver.badge(timeout: 15))
        Driver.both("\(tag)-probe-after", s)
    }
}
