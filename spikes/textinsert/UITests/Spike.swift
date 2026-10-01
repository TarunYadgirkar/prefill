import XCTest

@MainActor
enum Spike {
    static let host = "http://127.0.0.1:8805"
    static let page = URL(string: "http://localhost:8804/form.html")!
    static let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    static let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    static let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    static func snap(_ name: String, settle: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: settle)
        _ = try? Data(contentsOf: URL(string: "\(host)/snap?name=\(name)")!)
    }

    static func tree(_ name: String, _ app: XCUIApplication) {
        note(name, app.debugDescription)
    }

    static func note(_ name: String, _ text: String) {
        var req = URLRequest(url: URL(string: "\(host)/tree?name=\(name)")!)
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

    static func firstButton(in app: XCUIApplication, matching labels: [String]) -> XCUIElement? {
        for label in labels {
            let b = app.buttons[label]
            if b.exists { return b }
        }
        for label in labels {
            let b = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            if b.exists { return b }
        }
        return nil
    }

    static func hittable(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'BackButton'", label)).firstMatch
    }
}
