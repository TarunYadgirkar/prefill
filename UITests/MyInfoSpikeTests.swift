import XCTest

// Spike: does Safari's AutoFill My Info point at the same contact as Contacts' My Info?
// Reads both rows, changes one, reads the other. Run with TEST_RUNNER_PREFILL_SPIKE=myinfo.
@MainActor
final class MyInfoSpikeTests: XCTestCase {
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PREFILL_SPIKE"] == "myinfo")
        continueAfterFailure = true
    }

    func testMyInfoIsOnePointer() throws {
        let safariStart = readMyInfo(path: ["Apps", "Safari", "AutoFill"], shot: "safari-start")
        let contactsStart = readMyInfo(path: ["Apps", "Contacts"], shot: "contacts-start")
        print("SPIKE start safari=\(safariStart) contacts=\(contactsStart)")

        pickMyInfo(path: ["Apps", "Contacts"], contact: "Casey Fivevalues", shot: "contacts-set-casey")
        let safariAfterContacts = readMyInfo(path: ["Apps", "Safari", "AutoFill"], shot: "safari-after-contacts")
        print("SPIKE after Contacts>Casey safari=\(safariAfterContacts)")

        pickMyInfo(path: ["Apps", "Safari", "AutoFill"], contact: "Drew Customfirst", shot: "safari-set-drew")
        let contactsAfterSafari = readMyInfo(path: ["Apps", "Contacts"], shot: "contacts-after-safari")
        print("SPIKE after Safari>Drew contacts=\(contactsAfterSafari)")
    }

    private func open(_ path: [String]) {
        settings.terminate()
        settings.launch()
        for label in path { tapRow(label) }
    }

    private func readMyInfo(path: [String], shot: String) -> String {
        open(path)
        let row = myInfoRow()
        attach(shot)
        let text = row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "|")
        return "\(row.label) value=\(row.value ?? "nil") texts=\(text)"
    }

    private func pickMyInfo(path: [String], contact: String, shot: String) {
        open(path)
        myInfoRow().tap()
        Thread.sleep(forTimeInterval: 2)
        attach(shot + "-picker")
        let cell = settings.descendants(matching: .any)[contact].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "no \(contact) in picker")
        cell.tap()
        Thread.sleep(forTimeInterval: 2)
        attach(shot)
    }

    private func myInfoRow() -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH 'My Info'")
        let row = settings.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no My Info row")
        for _ in 0..<8 where !row.isHittable { settings.swipeUp(velocity: .slow) }
        return row
    }

    private func tapRow(_ label: String) {
        let row = settings.descendants(matching: .any)[label].firstMatch
        _ = row.waitForExistence(timeout: 5)
        for _ in 0..<10 where !(row.exists && row.isHittable) { settings.swipeUp(velocity: .slow) }
        for _ in 0..<10 where !(row.exists && row.isHittable) { settings.swipeDown(velocity: .slow) }
        XCTAssertTrue(row.isHittable, "no \(label) row")
        row.tap()
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
