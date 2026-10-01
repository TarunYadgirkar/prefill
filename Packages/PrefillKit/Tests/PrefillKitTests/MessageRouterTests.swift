import Foundation
import Synchronization
import Testing
@testable import PrefillKit

final class MemoryStore: SharedStore {
    private let documents: Mutex<(state: AppState, events: ExtensionEvents)>

    init(_ state: AppState = AppState(), events: ExtensionEvents = ExtensionEvents()) {
        documents = Mutex((state, events))
    }

    var events: ExtensionEvents { documents.withLock { $0.events } }

    func readAppState() throws -> AppState { documents.withLock { $0.state } }
    func writeAppState(_ state: AppState) throws { documents.withLock { $0.state = state } }
    func readEvents() throws -> ExtensionEvents { documents.withLock { $0.events } }

    func appendEvents(usage: [UsageEvent], captures: [Capture]) throws {
        documents.withLock { $0.events = $0.events.appending(usage: usage, captures: captures) }
    }
}

private enum Page {
    static let siteA = "signup.site-a.example"
    static let siteB = "www.site-b.example"
    static let newEmail = "new.person@example.org"

    static func context(_ host: String, section: String? = nil) -> [String: Any] {
        var field: [String: Any] = ["kind": "email"]
        field["section"] = section
        return ["type": "pageContext", "host": host, "fields": [field, ["kind": "phone"]]]
    }

    static func signup(_ host: String, email: String) -> [String: Any] {
        [
            "type": "capture", "host": host, "hasPassword": true,
            "fields": [
                ["kind": "name", "value": "Alex Rivera", "autocomplete": "name", "label": "Full name"],
                ["kind": "email", "value": email, "autocomplete": "email", "name": "email", "label": "Email"]
            ]
        ]
    }

    static var gift: [String: Any] {
        [
            "type": "capture", "host": siteA, "hasPassword": false,
            "fields": [
                ["kind": "name", "value": "Jordan Lee", "name": "recipient_name", "label": "Recipient's name"],
                [
                    "kind": "email", "value": "jordan.lee@example.net", "name": "recipient_email",
                    "label": "Recipient's email"
                ],
                [
                    "kind": "address", "name": "recipient_street recipient_city", "section": "shipping",
                    "address": [
                        "street": "77 Gift Way", "city": "Oakland", "state": "", "postalCode": "94612", "country": ""
                    ]
                ]
            ]
        ]
    }
}

private let link = CardLink(
    contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
    original: Alex.card, snapshotAt: .daysAgo(30)
)

struct MessageRouterTests {
    private let gateway = FakeGateway()

    private func router(_ store: MemoryStore) -> MessageRouter {
        MessageRouter(store: store, gateway: gateway, now: { .testNow })
    }

    private func linked(_ settings: Settings = Settings()) -> MemoryStore {
        MemoryStore(AppState(values: Alex.allValues, settings: settings, cardLink: link))
    }

    private var firstEmail: String? {
        gateway.card.emails.first?.payload.display
    }

    @Test func pingGetsPong() {
        #expect(router(MemoryStore()).route(["type": "ping"]) == .pong)
    }

    @Test(arguments: [nil, "ping", ["type": 1], ["kind": "ping"]] as [(any Sendable)?])
    func anythingUnreadableGetsAnError(message: (any Sendable)?) {
        #expect(router(MemoryStore()).route(message) == .error(reason: "unknown message"))
    }

    @Test func theReplyIsAFoundationObjectForSafari() {
        let reply = MessageCoding.jsonObject(router(MemoryStore()).route(["type": "ping"]))
        #expect(reply as? [String: String] == ["type": "pong"])
    }

    @Test func pageContextBeforeSetUpLeavesTheCardAlone() {
        let reply = router(MemoryStore()).route(Page.context(Page.siteA))
        #expect(reply == .pageContext(PageContextResponse(status: .notSetUp)))
        #expect(gateway.fetches == 0)
    }

    @Test func pageContextWithMatchEachSiteOffLeavesTheCardAlone() {
        let reply = router(linked(Settings(matchEachSite: false))).route(Page.context(Page.siteA))
        #expect(reply == .pageContext(PageContextResponse(status: .off)))
        #expect(gateway.fetches == 0)
    }

    @Test func pageContextPutsTheValueUsedOnThisSiteFirst() {
        let store = linked()
        try? store.appendEvents(
            usage: [UsageEvent(valueID: Alex.schoolEmail.id, host: "site-a.example", date: .daysAgo(1))], captures: []
        )
        let router = router(store)
        #expect(router.route(Page.context(Page.siteA)) == .pageContext(PageContextResponse(status: .saved)))
        #expect(firstEmail == "alex.school@example.edu")
        #expect(router.route(Page.context(Page.siteA)) == .pageContext(PageContextResponse(status: .unchanged)))
        #expect(gateway.saves.count == 1)
    }

    @Test func aWorkHintPutsTheWorkEmailFirst() {
        let reply = router(linked()).route(Page.context(Page.siteB, section: "work"))
        #expect(reply == .pageContext(PageContextResponse(status: .saved)))
        #expect(firstEmail == "alex@work.example.org")
        #expect(gateway.saves.last?.author == CardWriter.transactionAuthor)
    }

    @Test func anUnreachableCardIsReportedWithAReason() {
        gateway.state.withLock { $0.fetchError = .noAccess }
        let reply = router(linked()).route(Page.context(Page.siteA))
        #expect(reply == .pageContext(PageContextResponse(status: .failed, reason: CardWriteFailure.noAccess.reason)))
    }

    @Test func captureBeforeSetUpStoresNothing() {
        let store = MemoryStore()
        let reply = router(store).route(Page.signup(Page.siteA, email: Page.newEmail))
        #expect(reply == .capture(CaptureResponse(saved: 0, review: 0, ignored: 2)))
        #expect(store.events == ExtensionEvents())
        #expect(gateway.fetches == 0)
    }

    @Test func aNewEmailFromASignUpGoesOnTheCardFirstForThatSite() throws {
        let store = linked()
        let reply = router(store).route(Page.signup(Page.siteA, email: Page.newEmail))
        #expect(reply == .capture(CaptureResponse(saved: 1, review: 0, ignored: 1)))
        #expect(firstEmail == Page.newEmail)
        #expect(gateway.card.emails.count == 4)
        let capture = try #require(store.events.captures.first)
        #expect(capture.verdict == .saved)
        #expect(capture.host == "site-a.example")
        #expect(store.events.usage.map(\.host) == ["site-a.example"])
    }

    @Test func eachSiteGetsTheEmailUsedThere() {
        let store = linked()
        let router = router(store)
        _ = router.route(Page.signup(Page.siteA, email: Page.newEmail))
        let duplicate = router.route(Page.signup(Page.siteB, email: "alex@work.example.org"))
        #expect(duplicate == .capture(CaptureResponse(saved: 0, review: 0, ignored: 1)))
        #expect(firstEmail == Page.newEmail)

        _ = router.route(Page.context(Page.siteB))
        #expect(firstEmail == "alex@work.example.org")
        _ = router.route(Page.context(Page.siteA))
        #expect(firstEmail == Page.newEmail)
    }

    @Test func aGiftRecipientNeverReachesTheCard() {
        let store = linked()
        let reply = router(store).route(Page.gift)
        #expect(reply == .capture(CaptureResponse(saved: 0, review: 0, ignored: 3)))
        #expect(gateway.card == Alex.card)
        #expect(gateway.saves.isEmpty)
        #expect(store.events == ExtensionEvents())
    }

    @Test func aValueThatCannotBeSavedWaitsForReview() throws {
        gateway.state.withLock { $0.saveError = .notWritable }
        let store = linked()
        let reply = router(store).route(Page.signup(Page.siteA, email: Page.newEmail))
        #expect(reply == .capture(CaptureResponse(saved: 0, review: 1, ignored: 1)))
        #expect(try #require(store.events.captures.first).verdict == .needsReview)
        #expect(gateway.card == Alex.card)
    }
}
