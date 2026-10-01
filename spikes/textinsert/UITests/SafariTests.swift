import XCTest

@MainActor
final class SafariTests: XCTestCase {
    var prefix: String { ProcessInfo.processInfo.environment["SPIKE_PREFIX"] ?? "x" }

    func openPage() -> XCUIApplication {
        let s = Spike.safari
        s.terminate()
        s.launch()
        let pageName = ProcessInfo.processInfo.environment["SPIKE_PAGE"] ?? "form.html"
        s.open(URL(string: "http://localhost:8804/\(pageName)")!)
        let web = s.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        XCTAssertTrue(web.textFields.firstMatch.waitForExistence(timeout: 10))
        return s
    }

    func field(_ s: XCUIApplication, _ index: Int) -> XCUIElement {
        s.webViews.firstMatch.textFields.element(boundBy: index)
    }

    func caretMenu(_ s: XCUIApplication, _ f: XCUIElement) {
        f.tap()
        Thread.sleep(forTimeInterval: 1)
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        _ = s.menuItems["AutoFill"].waitForExistence(timeout: 3)
    }

    var fieldIndex: Int { Int(ProcessInfo.processInfo.environment["SPIKE_FIELD"] ?? "1") ?? 1 }

    func testExploreMenus() {
        var lines: [String] = []
        let s = openPage()
        let f = field(s, fieldIndex)
        let tag = "\(prefix)-f\(fieldIndex)"
        caretMenu(s, f)
        Thread.sleep(forTimeInterval: 1.5)
        Spike.both("\(tag)-1-edit-menu", s, settle: 0.2)
        lines.append("edit menu: \(menuSummary(s))")
        s.menuItems["AutoFill"].tap()
        Spike.both("\(tag)-2-autofill-submenu", s, settle: 1)
        let pw = s.buttons["Passwords"]
        lines.append("submenu has Passwords: \(pw.exists)")
        guard pw.exists else { return Spike.note("\(tag)-explore", lines.joined(separator: "\n")) }
        pw.tap()
        for i in 1...6 { Spike.snap("\(tag)-3-after-passwords-seq\(i)", settle: 0.25) }
        Spike.both("\(tag)-3-after-passwords", s, settle: 2.5)
        Spike.tree("\(tag)-3-after-passwords-springboard", Spike.springboard)
        lines.append("after Passwords menu: \(menuSummary(s))")
        Spike.note("\(tag)-explore", lines.joined(separator: "\n"))
    }

    func menuItem(_ s: XCUIApplication, _ label: String) -> XCUIElement? {
        let q = s.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        return q.exists ? q : nil
    }

    func menuSummary(_ s: XCUIApplication) -> String {
        let items = s.menuItems.allElementsBoundByIndex.map(\.label)
        let sbItems = Spike.springboard.menuItems.allElementsBoundByIndex.map(\.label)
        return "app=\(items) springboard=\(sbItems)"
    }

    func testMenuVariants() {
        var lines: [String] = []
        var s = openPage()
        field(s, 0).press(forDuration: 1.0)
        Spike.both("\(prefix)-variantA-longpress-unfocused", s)
        lines.append("A longpress unfocused: \(menuSummary(s))")

        s = openPage()
        let f = field(s, 0)
        f.tap()
        Thread.sleep(forTimeInterval: 1)
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        Spike.both("\(prefix)-variantB-tap-caret", s)
        lines.append("B tap caret: \(menuSummary(s))")

        f.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).press(forDuration: 1.0)
        Spike.both("\(prefix)-variantC-longpress-caret", s)
        lines.append("C longpress caret focused: \(menuSummary(s))")

        s.webViews.firstMatch.staticTexts["Email"].tap()
        Thread.sleep(forTimeInterval: 1)
        f.doubleTap()
        Spike.both("\(prefix)-variantD-doubletap", s)
        lines.append("D doubletap: \(menuSummary(s))")
        Spike.note("\(prefix)-menu-variants", lines.joined(separator: "\n"))
    }

    func testAutoFillItemPerField() {
        var lines: [String] = []
        for (i, name) in ["tagged", "untagged", "tel"].enumerated() {
            let s = openPage()
            let f = field(s, i)
            caretMenu(s, f)
            Thread.sleep(forTimeInterval: 1.5)
            lines.append("\(name) menu: \(menuSummary(s))")
            Spike.snap("\(prefix)-perfield-\(name)-menu", settle: 0.2)
            let item = s.menuItems["AutoFill"]
            guard item.exists else { continue }
            if name == "tagged" { item.press(forDuration: 0.4) } else { item.tap() }
            Spike.snap("\(prefix)-perfield-\(name)-after-autofill", settle: 0.8)
            Spike.tree("\(prefix)-perfield-\(name)-after-autofill", s)
            let btns = s.buttons.allElementsBoundByIndex.map(\.label).filter { ["Contact", "Passwords", "Credit Card"].contains($0) }
            lines.append("\(name) after AutoFill: \(menuSummary(s)) buttons=\(btns)")
        }
        Spike.note("\(prefix)-perfield", lines.joined(separator: "\n"))
    }

    var value: String { ProcessInfo.processInfo.environment["SPIKE_VALUE"] ?? "ti-one@example.net" }

    func testInsertFlow() {
        var lines: [String] = []
        var taps = 0
        let s = openPage()
        let f = field(s, fieldIndex)
        let tag = "\(prefix)-ins-f\(fieldIndex)"
        f.tap(); taps += 1
        Thread.sleep(forTimeInterval: 1)
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap(); taps += 1
        _ = s.menuItems["AutoFill"].waitForExistence(timeout: 3)
        Thread.sleep(forTimeInterval: 1.5)
        Spike.both("\(tag)-1-edit-menu", s, settle: 0.2)
        lines.append("edit menu: \(menuSummary(s))")
        s.menuItems["AutoFill"].tap(); taps += 1
        let pw = s.buttons["Passwords"]
        guard pw.waitForExistence(timeout: 3) else {
            Spike.both("\(tag)-2-no-submenu", s)
            lines.append("submenu missing after AutoFill")
            return Spike.note("\(tag)-flow", lines.joined(separator: "\n"))
        }
        Spike.both("\(tag)-2-autofill-submenu", s, settle: 0.5)
        pw.tap(); taps += 1
        let chooser = Spike.hittable(s, "Prefill Spike")
        if chooser.waitForExistence(timeout: 5) {
            Spike.both("\(tag)-3-provider-chooser", s, settle: 0.5)
            lines.append("chooser: Passwords=\(s.buttons["Passwords"].exists) PrefillSpike=\(chooser.exists) Cancel=\(s.buttons["Cancel"].exists)")
            chooser.tap(); taps += 1
        } else {
            lines.append("no provider chooser shown")
        }
        let target = s.buttons[value]
        let appeared = target.waitForExistence(timeout: 10)
        Spike.both("\(tag)-4-provider-ui", s, settle: 1)
        Spike.tree("\(tag)-4-provider-ui-springboard", Spike.springboard)
        lines.append("provider value button visible in Safari tree: \(appeared)")
        guard appeared else { return Spike.note("\(tag)-flow", lines.joined(separator: "\n")) }
        target.tap(); taps += 1
        Spike.both("\(tag)-5-after-insert", s, settle: 2)
        lines.append("field value after insert: \(String(describing: f.value))")
        lines.append("user taps from unfocused field to inserted value: \(taps)")
        Spike.note("\(tag)-flow", lines.joined(separator: "\n"))
    }
}
