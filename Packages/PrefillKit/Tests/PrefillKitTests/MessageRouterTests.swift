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

    func removeAll() throws {
        documents.withLock { $0 = (AppState(), ExtensionEvents()) }
    }

    func appendEvents(_ new: ExtensionEvents) throws {
        documents.withLock { $0.events = $0.events.appending(new) }
    }

    // Stands in for review spam having trimmed every capture record away.
    func removeCaptures() throws {
        documents.withLock { documents in
            let events = documents.events
            documents.events = ExtensionEvents(
                usage: events.usage, saves: events.saves, pins: events.pins,
                mutes: events.mutes
            )
        }
    }
}

private enum Page {
    static let siteA = "signup.site-a.example"
    static let siteB = "www.site-b.example"
    static let newEmail = "new.person@example.org"

    static func suggestions(_ host: String, section: String? = nil) -> [String: Any] {
        var field: [String: Any] = ["kind": "email"]
        field["section"] = section
        return ["type": "contactSuggestions", "host": host, "fields": [field, ["kind": "phone"]]]
    }

    static func signup(_ host: String, email: String, submitted: Bool = true) -> [String: Any] {
        signup(host, emails: [email], submitted: submitted)
    }

    static func signup(_ host: String, emails: [String], submitted: Bool = true) -> [String: Any] {
        let name: [String: Any] = [
            "kind": "name", "userTyped": true, "value": "Alex Rivera", "autocomplete": "name", "label": "Full name"
        ]
        let typed = emails.map {
            ["kind": "email", "userTyped": true, "value": $0, "autocomplete": "email", "name": "email"]
        }
        return [
            "type": "capture", "host": host, "hasPassword": true, "trigger": submitted ? "submit" : "flush",
            "fields": [name] + typed
        ]
    }

    static var gift: [String: Any] {
        [
            "type": "capture", "host": siteA, "hasPassword": false, "trigger": "submit",
            "fields": [
                [
                    "kind": "name", "userTyped": true, "value": "Jordan Lee", "name": "recipient_name",
                    "label": "Recipient's name"
                ],
                [
                    "kind": "email", "userTyped": true, "value": "jordan.lee@example.net", "name": "recipient_email",
                    "label": "Recipient's email"
                ],
                [
                    "kind": "address", "userTyped": true, "name": "recipient_street recipient_city",
                    "section": "shipping",
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

    private func firstSuggested(_ reply: ExtensionResponse) -> String? {
        guard case .contactSuggestions(let body) = reply else { return nil }
        return body.emails.first?.value
    }

    @Test func aRetiredPageContextIsAnUnknownMessage() {
        let reply = router(linked()).route(["type": "pageContext", "host": Page.siteA, "fields": [["kind": "email"]]])
        #expect(reply == .error(reason: "unknown message"))
        #expect(gateway.fetches == 0)
    }

    @Test func aPageWithFormsConfirmsTheExtensionRunsOnWebsites() throws {
        let store = MemoryStore()
        _ = router(store).route(Page.suggestions(Page.siteA))
        #expect(try store.readEvents().lastPageSeen == .testNow)
    }

    @Test func aPageWithFormsRecordsSightingsAtMostDaily() throws {
        let earlier = Date.testNow.addingTimeInterval(-3_600)
        let store = MemoryStore()
        try store.appendEvents(ExtensionEvents(lastPageSeen: earlier))
        _ = router(store).route(Page.suggestions(Page.siteA))
        #expect(try store.readEvents().lastPageSeen == earlier)
    }

    // Prefill's list does the ranking for the page; the card keeps one order everywhere.
    @Test func theValueUsedOnThisSiteComesFirstWithoutACardWrite() {
        let store = linked()
        try? store.appendEvents(
            usage: [UsageEvent(valueID: Alex.schoolEmail.id, host: "site-a.example", date: .daysAgo(1))], captures: []
        )
        #expect(firstSuggested(router(store).route(Page.suggestions(Page.siteA))) == "alex.school@example.edu")
        #expect(gateway.saves.isEmpty)
        #expect(firstEmail == Alex.card.emails.first?.payload.display)
    }

    @Test func aWorkHintPutsTheWorkEmailFirst() {
        let reply = router(linked()).route(Page.suggestions(Page.siteB, section: "work"))
        #expect(firstSuggested(reply) == "alex@work.example.org")
        #expect(gateway.saves.isEmpty)
    }

    @Test func aSiteKindFromTheModelPutsTheWorkEmailFirst() {
        let store = MemoryStore(
            AppState(values: Alex.allValues, cardLink: link, siteKinds: ["site-b.example": .work])
        )
        #expect(firstSuggested(router(store).route(Page.suggestions(Page.siteB))) == "alex@work.example.org")
    }

    @Test func theFocusLabelReachesPagesFromSafari() {
        let reply = router(linked(Settings(focusLabel: "work"))).route(Page.suggestions(Page.siteA))
        #expect(firstSuggested(reply) == "alex@work.example.org")
    }

    @Test func anUnreachableCardSuggestsNothing() {
        gateway.state.withLock { $0.fetchError = .noAccess }
        let reply = router(linked()).route(Page.suggestions(Page.siteA))
        #expect(reply == .contactSuggestions(ContactSuggestionsResponse()))
    }

    @Test func captureBeforeSetUpStoresNothing() {
        let store = MemoryStore()
        let reply = router(store).route(Page.signup(Page.siteA, email: Page.newEmail))
        #expect(reply == .capture(CaptureResponse(saved: 0, review: 0, ignored: 2)))
        #expect(store.events == ExtensionEvents())
        #expect(gateway.fetches == 0)
    }

    // The card gains the value at the end and keeps its order; Prefill's list puts it first.
    @Test func aNewEmailFromASignUpGoesOnTheCardAndFirstInTheListForThatSite() throws {
        let store = linked()
        let reply = router(store).route(Page.signup(Page.siteA, email: Page.newEmail))
        #expect(reply == .capture(CaptureResponse(saved: 1, review: 0, ignored: 1)))
        #expect(gateway.card.emails.map(\.payload.display) == Alex.card.emails.map(\.payload.display) + [Page.newEmail])
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
        #expect(firstSuggested(router.route(Page.suggestions(Page.siteB))) == "alex@work.example.org")
        #expect(firstSuggested(router.route(Page.suggestions(Page.siteA))) == Page.newEmail)
        #expect(firstEmail == Alex.card.emails.first?.payload.display)
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

    @Test func aPageThatWasOnlyHiddenNeverWritesTheCard() throws {
        let store = linked()
        let reply = router(store).route(Page.signup(Page.siteA, email: Page.newEmail, submitted: false))
        #expect(reply == .capture(CaptureResponse(saved: 0, review: 1, ignored: 1)))
        #expect(gateway.saves.isEmpty)
        #expect(try #require(store.events.captures.first).verdict == .needsReview)
    }

    @Test func oneFormSavesAtMostThreeNewValues() {
        let emails = (1...5).map { "new\($0)@example.org" }
        let reply = router(linked()).route(Page.signup(Page.siteA, emails: emails))
        #expect(reply == .capture(CaptureResponse(saved: 3, review: 2, ignored: 1)))
        #expect(gateway.card.emails.count == 6)
    }

    @Test func savesAcrossSitesAreCappedPerHour() {
        let recent = (0..<5).map { index in
            Capture(
                host: "elsewhere.example", value: Alex.value(.email("old\(index)@example.org"), label: nil),
                date: .testNow.addingTimeInterval(-600), verdict: .saved
            )
        }
        let store = linked()
        try? store.appendEvents(usage: [], captures: recent)
        let reply = router(store).route(Page.signup(Page.siteA, emails: ["a@example.org", "b@example.org"]))
        #expect(reply == .capture(CaptureResponse(saved: 1, review: 1, ignored: 1)))
    }

    @Test func theHourlyLimitHoldsAfterSavedRecordsAreTrimmed() {
        let store = linked()
        let router = router(store)
        _ = router.route(Page.signup(Page.siteA, emails: ["a@example.org", "b@example.org", "c@example.org"]))
        _ = router.route(Page.signup(Page.siteB, emails: ["d@example.org", "e@example.org", "f@example.org"]))
        try? store.removeCaptures()
        let reply = router.route(Page.signup(Page.siteA, email: "g@example.org"))
        #expect(reply == .capture(CaptureResponse(saved: 0, review: 1, ignored: 1)))
    }

    @Test func oneSiteCanFileOnlySoManyValuesForReviewEachDay() {
        let store = linked()
        let router = router(store)
        let batches = (0..<3).map { batch in (0..<10).map { "flushed\(batch)-\($0)@example.org" } }
        let replies = batches.map { router.route(Page.signup(Page.siteA, emails: $0, submitted: false)) }
        #expect(replies.last == .capture(CaptureResponse(saved: 0, review: 0, ignored: 11)))
        #expect(store.events.captures.count == MessageRouter.maxReviewsPerSite)
        let elsewhere = router.route(Page.signup(Page.siteB, email: Page.newEmail, submitted: false))
        #expect(elsewhere == .capture(CaptureResponse(saved: 0, review: 1, ignored: 1)))
    }

    @Test func withMatchEachSiteOffNoUseIsRecorded() throws {
        let store = linked(Settings(matchEachSite: false))
        let router = router(store)
        _ = router.route(Page.signup(Page.siteA, email: Page.newEmail))
        _ = router.route(Page.signup(Page.siteB, email: "alex@work.example.org"))
        #expect(store.events.usage.isEmpty)
        #expect(try #require(store.events.captures.first).verdict == .saved)
    }

    @Test func aCaptureReadsTheCardOnce() {
        _ = router(linked()).route(Page.signup(Page.siteA, email: Page.newEmail))
        #expect(gateway.fetches == 1)
    }
}
