import Foundation
import XCTest

// The Mac-side helper started by scripts/test.sh e2e (scripts/e2e-server.py). The
// simulator shares the Mac's loopback, so both test sites and the helper live there.
struct E2EServer {
    struct Card: Decodable, Equatable {
        let emails: [String]
        let phones: [String]
        let addressCount: Int
        let linkCount: Int
    }

    static let port = 8846
    static let control = URL(string: "http://127.0.0.1:\(port)")!

    enum Site: String {
        case siteA = "localhost"
        case siteB = "127.0.0.1"

        func page(_ name: String) -> URL {
            URL(string: "http://\(rawValue):\(E2EServer.port)/\(name)?r=\(Int(Date().timeIntervalSince1970))")!
        }
    }

    static func fetch(_ path: String, timeout: TimeInterval = 15) -> Data? {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var body: Data?
        let url = URL(string: "\(control.absoluteString)/\(path)")!
        let task = URLSession.shared.dataTask(with: url) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { body = data }
            done.signal()
        }
        task.resume()
        _ = done.wait(timeout: .now() + timeout)
        return body
    }

    static var isRunning: Bool { fetch("card", timeout: 3) != nil }

    static func card() -> Card? {
        fetch("card").flatMap { try? JSONDecoder().decode(Card.self, from: $0) }
    }

    // Saved as assets/generated/e2e-ext-<name>.png by the helper (minimal-card-* names keep theirs).
    static func screenshot(_ name: String) {
        _ = fetch("snap?name=\(name)")
    }

    static func waitForCard(timeout: TimeInterval = 20, until done: (Card) -> Bool) -> Card? {
        let deadline = Date().addingTimeInterval(timeout)
        var last = card()
        while Date() < deadline {
            if let card = last, done(card) { return card }
            Thread.sleep(forTimeInterval: 1)
            last = card()
        }
        return last
    }
}
