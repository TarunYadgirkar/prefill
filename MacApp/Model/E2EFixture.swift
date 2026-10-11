#if PREFILL_TEST_BROWSERS
import AppKit
import Foundation
import PrefillKit
import Synchronization

// scripts/e2e-mac-chrome.sh runs a test build with a fixed card and its own store, so the
// browser check never needs a Contacts prompt answered or touches the person's card.
enum E2EFixture {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var store: (any SharedStore)? {
        environment["PREFILL_E2E_STORE"].map { AppGroupStore(directory: URL(filePath: $0)) }
    }

    static var isShowcase: Bool { environment["PREFILL_E2E_SHOWCASE"] == "1" }

    static var gateway: FixtureGateway? {
        guard let path = environment["PREFILL_E2E_CARD"],
              let data = try? Data(contentsOf: URL(filePath: path)),
              let card = try? JSONDecoder().decode(CardRecord.self, from: data) else { return nil }
        return FixtureGateway(card: card)
    }
}

// The menu's inbox and history for screenshots: two values waiting, a learned answer and
// three sent applications, all for the Alex Rivera card. `.example` hosts can't be real sites.
extension E2EFixture {
    static func seedShowcase(_ store: any SharedStore) {
        let now = Date.now
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3_600) }
        let phone = ContactValue(
            payload: .phone("+1 (510) 555-0172"), label: nil, source: .captured, createdAt: ago(26)
        )
        let email = ContactValue(
            payload: .email("alex.rivera@learn.example.edu"), label: nil, source: .captured, createdAt: ago(4)
        )
        let captures = [
            Capture(host: "bluebird-tickets.example", value: phone, date: ago(26), verdict: .needsReview),
            Capture(host: "courses.example.edu", value: email, date: ago(4), verdict: .needsReview)
        ]
        let answers = [
            LearnedAnswer(host: "jobs.lumen-robotics.example", label: "Graduation", value: "May 2027", date: ago(3))
        ]
        let fields = [ApplicationRequest.Field(question: "School", answer: "University of California, Berkeley")]
        let sent = [
            ("jobs.lumen-robotics.example", "Software Engineering Intern, Lumen Robotics", 3.0),
            ("apply.harborline.example", "Product Design Fellowship, Harborline", 27.0),
            ("careers.tidewater-labs.example", "Research Assistant, Tidewater Labs", 75.0)
        ]
        let applications = sent.map { host, title, hours in
            SubmittedApplication(
                date: ago(hours),
                request: ApplicationRequest(host: host, path: "/apply", title: title, fields: fields, files: [])
            )
        }
        try? store.appendEvents(ExtensionEvents(captures: captures, answers: answers, applications: applications))
    }
}

extension E2EFixture {
    // Draws each showcase window into <PREFILL_E2E_SNAP>/mac-<title>.png once it has settled.
    // The window draws itself, so this needs no Screen Recording permission.
    @MainActor static func snapWindowsLater() {
        guard let folder = environment["PREFILL_E2E_SNAP"] else { return }
        if let look = environment["PREFILL_E2E_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            for window in NSApp.windows where window.isVisible && window.title.hasPrefix("Prefill") {
                // Prominent buttons draw gray in a window that isn't key.
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(500))
                // The frame view draws the window's background; the content view alone is clear.
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = window.title.lowercased().replacingOccurrences(of: " ", with: "-")
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(filePath: folder).appending(path: "\(name).png"))
            }
        }
    }
}

final class FixtureGateway: ContactsGateway {
    private let card: Mutex<CardRecord>

    init(card: CardRecord) {
        self.card = Mutex(card)
    }

    var link: CardLink {
        let current = card.withLock { $0 }
        return CardLink(
            contactIdentifier: current.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: current, snapshotAt: .now
        )
    }

    func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        let current = card.withLock { $0 }
        guard current.identifier == identifier else { throw .cardMissing }
        return current
    }

    func save(_ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String)
        throws(CardWriteFailure) -> CardSaveResult {
        card.withLock { $0 = target }
        return .saved
    }
}
#endif
