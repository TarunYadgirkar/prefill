import XCTest

// Drives Settings and Safari for the extension end-to-end test. Recipes come from
// spikes/capture/UITests and spikes/datalist/UITests.
@MainActor
enum SafariDriver {
    static let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    static let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private static let extensionName = "Prefill"

    // Settings > Apps > Safari > Extensions > Prefill: Allow Extension on, All Websites: Allow.
    static func enableExtension() {
        settings.terminate()
        settings.launch()
        popToRoot(settings)
        for label in ["Apps", "Safari", "Extensions", extensionName] {
            tapRow(label, in: settings)
        }
        let toggle = settings.switches["Allow Extension"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no Allow Extension switch")
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        tapRow("All Websites", in: settings)
        tapRow("Allow", in: settings)
        E2EServer.screenshot("settings-all-websites-allow")
        settings.terminate()
        safari.terminate()
    }

    static func open(_ url: URL, waitingFor field: String) {
        safari.open(url)
        XCTAssertTrue(self.field(field).waitForExistence(timeout: 20), "page \(url.path()) never showed \(field)")
    }

    static func field(_ label: String) -> XCUIElement {
        let types = [XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.secureTextField.rawValue]
        let predicate = NSPredicate(format: "label BEGINSWITH %@ AND elementType IN %@", label, types)
        return safari.webViews.descendants(matching: .any).matching(predicate).firstMatch
    }

    static func type(_ text: String, into label: String) {
        let element = field(label)
        XCTAssertTrue(element.waitForExistence(timeout: 10), "no field \(label)")
        element.tap()
        Thread.sleep(forTimeInterval: 0.8)
        element.typeText(text)
        dismissKeyboard()
    }

    static func tapButton(_ label: String) {
        let button = safari.webViews.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no button \(label)")
        button.tap()
    }

    static func waitForText(_ text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return safari.webViews.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 20)
    }

    static func dismissKeyboard() {
        for label in ["Done", "done"] where safari.buttons[label].exists && safari.buttons[label].isHittable {
            safari.buttons[label].tap()
            Thread.sleep(forTimeInterval: 0.6)
            return
        }
    }

    // Focuses the field and reads Safari's own QuickType bar from the accessibility tree,
    // left to right. Each suggestion's label is the contact label, a newline, the value.
    static func suggestions(focusing label: String) -> [String] {
        field(label).tap()
        let bar = safari.otherElements["Typing Predictions"].firstMatch
        guard bar.waitForExistence(timeout: 8) else { return [] }
        Thread.sleep(forTimeInterval: 0.5)
        return bar.buttons.allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
            .map(\.label)
    }

    // One row of Prefill's own list: the value and the caption under it ("Email", "GitHub").
    struct Row {
        let value: String
        let detail: String
    }

    // Focuses the field and reads which of `rows` Prefill's list shows, top to bottom, retrying
    // while the app answers. The list is Prefill's, not Safari's bar above the keyboard.
    static func prefillList(focusing label: String, rows: [Row]) -> [String] {
        var shown: [String] = []
        for _ in 0..<4 {
            field(label).tap()
            Thread.sleep(forTimeInterval: 1.5)
            shown = prefillRows(rows)
            if !shown.isEmpty { break }
            dismissKeyboard()
            Thread.sleep(forTimeInterval: 2)
        }
        return shown
    }

    // A row reads as its value then its caption. Safari's suggestion bubble and the keyboard's
    // bar show some of the same values with other captions, and a combined link row starts
    // with a single link's text, so a row has to match both and nothing more.
    static func prefillRows(_ rows: [Row]) -> [String] {
        let found = rows.compactMap { row -> (String, CGFloat)? in
            let predicate = NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", row.value, row.detail)
            let element = safari.webViews.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
                .first { $0.label.count <= row.value.count + row.detail.count + 2 }
            return element.map { (row.value, $0.frame.minY) }
        }
        return found.sorted { $0.1 < $1.1 }.map(\.0)
    }

    // Safari's page menu, then Prefill's row, which opens the extension's sheet.
    static func openPrefillSheet() {
        let menu = safari.buttons["MoreMenuButton"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no page menu button")
        menu.tap()
        let row = safari.buttons[extensionName].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Prefill row in the page menu")
        row.tap()
    }

    // Swipes the sheet down by its top edge, the way a person closes it.
    static func closeSheet(from element: XCUIElement) {
        let top = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        let start = top.withOffset(CGVector(dx: 0, dy: -40))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 700)))
        Thread.sleep(forTimeInterval: 1.5)
    }

    // Settings can reopen where it was left, so walk back to its first page.
    private static func popToRoot(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        for _ in 0..<6 where back.waitForExistence(timeout: 2) {
            back.tap()
        }
    }

    // Scrolls down to the row, then back up if it was above the visible part.
    private static func tapRow(_ label: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any)[label].firstMatch
        _ = row.waitForExistence(timeout: 5)
        for _ in 0..<10 where !(row.exists && row.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        for _ in 0..<10 where !(row.exists && row.isHittable) {
            app.swipeDown(velocity: .slow)
        }
        if !row.isHittable { E2EServer.screenshot("settings-missing-row") }
        XCTAssertTrue(row.isHittable, "no \(label) row")
        row.tap()
        Thread.sleep(forTimeInterval: 1.5)
    }
}
