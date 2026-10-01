import XCTest

@MainActor
final class DriverTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let server = "http://127.0.0.1:8801"

    override func setUp() async throws {
        continueAfterFailure = true
    }

    func testSafariField() throws {
        let step = env["STEP"] ?? "unnamed"
        safari.activate()
        _ = safari.wait(for: .runningForeground, timeout: 10)
        sleep(2)
        if let field = env["FIELD"], !field.isEmpty {
            let target = safari.textFields[field].firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 10), "field \(field) not found")
            target.tap()
            if let text = env["TYPE"], !text.isEmpty {
                sleep(2)
                safari.typeText(text)
            }
            sleep(UInt32(env["SETTLE"] ?? "3") ?? 3)
        }
        post(["src": "uitest", "event": "focused", "step": step, "tree": safari.debugDescription])
        waitForSignal("\(step)-1")
        if let text = env["TAP"], !text.isEmpty {
            tapSuggestion(text, step: step)
            sleep(2)
            post(["src": "uitest", "event": "after-tap", "step": step, "tree": safari.debugDescription])
            waitForSignal("\(step)-2")
        }
    }

    func testDump() throws {
        let app = XCUIApplication(bundleIdentifier: env["BUNDLE"] ?? "com.apple.Preferences")
        app.activate()
        sleep(2)
        post(["src": "uitest", "event": "dump", "step": env["STEP"] ?? "dump", "tree": app.debugDescription])
    }

    func testEnableExtension() throws {
        settings.terminate()
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        let steps = (env["PATH_LABELS"] ?? "Apps|Safari|Extensions|Datalist Spike").split(separator: "|").map(String.init)
        for label in steps {
            let cell = settings.descendants(matching: .any)[label].firstMatch
            scrollTo(cell, in: settings)
            XCTAssertTrue(cell.exists, "missing \(label)")
            cell.tap()
            sleep(2)
        }
        post(["src": "uitest", "event": "extension-page", "step": env["STEP"] ?? "enable", "tree": settings.debugDescription])
        waitForSignal("\(env["STEP"] ?? "enable")-1")
    }

    func testTapLabels() throws {
        let app = XCUIApplication(bundleIdentifier: env["BUNDLE"] ?? "com.apple.Preferences")
        app.activate()
        sleep(1)
        let step = env["STEP"] ?? "tap"
        for label in (env["LABELS"] ?? "").split(separator: "|").map(String.init) {
            if label.hasPrefix("switch:") {
                let sw = app.switches[String(label.dropFirst(7))].firstMatch
                scrollTo(sw, in: app)
                XCTAssertTrue(sw.exists, "missing \(label)")
                sw.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                sleep(2)
                continue
            }
            let el = app.descendants(matching: .any)[label].firstMatch
            scrollTo(el, in: app)
            XCTAssertTrue(el.exists, "missing \(label)")
            if el.exists { el.tap() }
            sleep(2)
        }
        post(["src": "uitest", "event": "after-labels", "step": step, "tree": app.debugDescription])
        waitForSignal("\(step)-1")
    }

    private func tapSuggestion(_ text: String, step: String) {
        let scope: XCUIElement = switch env["TAP_IN"] ?? "bar" {
        case "bar": safari.otherElements["Typing Predictions"].firstMatch
        case "suggested": safari.otherElements["Suggested"].firstMatch
        default: safari.collectionViews.firstMatch
        }
        let candidates = scope.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text))
        let match = candidates.allElementsBoundByIndex.first { $0.isHittable }
        post(["src": "uitest", "event": "tap-candidate", "step": step, "found": match.map { "\($0.elementType.rawValue) \($0.label) \($0.frame)" } ?? "none"])
        match?.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }

    private func waitForSignal(_ name: String) {
        let url = URL(string: "\(server)/signal/\(name)")!
        let deadline = Date().addingTimeInterval(Double(env["HOLD"] ?? "90") ?? 90)
        while Date() < deadline {
            if fetchStatus(url) == 200 { return }
            sleep(1)
        }
    }

    private func fetchStatus(_ url: URL) -> Int {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var status = 0
        URLSession.shared.dataTask(with: url) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            sem.signal()
        }.resume()
        sem.wait()
        return status
    }

    private func post(_ body: [String: String]) {
        var request = URLRequest(url: URL(string: "\(server)/log")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
        sem.wait()
    }
}
