import XCTest

@MainActor
enum Driver {
    static let snapHost = "http://127.0.0.1:8824"
    static let web = "http://127.0.0.1:8803/web"
    static let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    static let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    static let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    static func snap(_ name: String, settle: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: settle)
        _ = try? Data(contentsOf: URL(string: "\(snapHost)/snap?name=\(name)")!)
    }

    static func tree(_ name: String, _ app: XCUIApplication) {
        var req = URLRequest(url: URL(string: "\(snapHost)/tree?name=\(name)")!)
        req.httpMethod = "POST"
        req.httpBody = Data(app.debugDescription.utf8)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in done.signal() }.resume()
        done.wait()
    }

    static func note(_ name: String, _ text: String) {
        var req = URLRequest(url: URL(string: "\(snapHost)/tree?name=\(name)")!)
        req.httpMethod = "POST"
        req.httpBody = Data(text.utf8)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in done.signal() }.resume()
        done.wait()
    }

    static func both(_ name: String, _ app: XCUIApplication, settle: TimeInterval = 1.0) {
        snap(name, settle: settle)
        tree(name, app)
    }

    static func open(_ page: String) {
        let bust = (page.contains("?") ? "&" : "?") + "r=\(Int(Date().timeIntervalSince1970))"
        safari.open(URL(string: "\(web)/\(page)\(bust)")!)
        Thread.sleep(forTimeInterval: 3)
    }

    static func field(_ label: String) -> XCUIElement {
        safari.webViews.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND (elementType == %d OR elementType == %d)", label, XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.secureTextField.rawValue)).firstMatch
    }

    static func type(_ text: String, into label: String) {
        let el = field(label)
        XCTAssertTrue(el.waitForExistence(timeout: 10), "field \(label) missing")
        el.tap()
        Thread.sleep(forTimeInterval: 0.8)
        el.typeText(text)
        dismissKeyboard()
    }

    static func dismissKeyboard() {
        for label in ["Done", "done"] {
            let b = safari.buttons[label]
            if b.exists && b.isHittable { b.tap(); Thread.sleep(forTimeInterval: 0.6); return }
        }
    }

    static func badge(timeout: TimeInterval = 8) -> String {
        let el = safari.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Captured' OR label BEGINSWITH 'Capture failed'")).firstMatch
        return el.waitForExistence(timeout: timeout) ? el.label : "no badge"
    }
}
