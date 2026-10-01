import XCTest

@MainActor
final class DriverTests: XCTestCase {
    private var app = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testScript() throws {
        let script = ProcessInfo.processInfo.environment["PROBE_SCRIPT"] ?? "dump"
        for step in script.components(separatedBy: ";;") where !step.isEmpty {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let arg = parts.count > 1 ? parts[1] : ""
            print("[driver] step \(parts[0]) \(arg)")
            try perform(parts[0], arg)
        }
    }

    private func perform(_ command: String, _ arg: String) throws {
        switch command {
        case "app": app = XCUIApplication(bundleIdentifier: arg); app.activate()
        case "use": app = XCUIApplication(bundleIdentifier: arg)
        case "launch": app = XCUIApplication(bundleIdentifier: arg); app.launch()
        case "probe": launchProbe(arg)
        case "tap": try element(arg).tap()
        case "tapWeb": try webField(arg).tap()
        case "type": app.typeText(arg)
        case "wait": Thread.sleep(forTimeInterval: Double(arg) ?? 1)
        case "dump": print("[driver] tree\n\(app.debugDescription)")
        case "keyboard": dumpKeyboard()
        case "maybeTap": maybeTap(arg)
        case "stamp": print("[driver] stamp \(arg) \(Date().timeIntervalSince1970)")
        default: XCTFail("unknown step \(command)")
        }
    }

    private func launchProbe(_ action: String) {
        app = XCUIApplication()
        app.launchArguments = action.isEmpty ? [] : ["-action"] + action.split(separator: " ").map(String.init)
        app.launch()
    }

    private func element(_ label: String) throws -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        guard match.waitForExistence(timeout: 10) else {
            print("[driver] missing \(label)\n\(app.debugDescription)")
            throw XCTSkip("missing \(label)")
        }
        return match
    }

    private func maybeTap(_ label: String) {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        if match.waitForExistence(timeout: 4) { match.tap() } else { print("[driver] maybeTap: no \(label)") }
    }

    private func webField(_ label: String) throws -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR placeholderValue CONTAINS[c] %@", label, label)
        let field = app.webViews.textFields.matching(predicate).firstMatch
        guard field.waitForExistence(timeout: 15) else {
            print("[driver] missing web field \(label)\n\(app.debugDescription)")
            throw XCTSkip("missing web field \(label)")
        }
        return field
    }

    private func dumpKeyboard() {
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 1.5)
        let labels = app.descendants(matching: .any).allElementsBoundByAccessibilityElement
            .filter { $0.frame.minY > app.frame.height * 0.45 }
            .map { "\($0.elementType.rawValue)|\($0.label)|\($0.identifier)" }
        print("[driver] lower-half elements: \(labels.joined(separator: " ;; "))")
    }
}
