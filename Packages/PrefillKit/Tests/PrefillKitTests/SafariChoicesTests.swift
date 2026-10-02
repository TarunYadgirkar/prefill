import Foundation
import Testing
@testable import PrefillKit

private let site = "site-a.example"
private let alexLink = CardLink(
    contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
    original: Alex.card, snapshotAt: .daysAgo(30)
)

struct SafariChoicesTests {
    private let gateway = FakeGateway()

    private func router(_ store: MemoryStore) -> MessageRouter {
        MessageRouter(store: store, gateway: gateway, now: { .testNow })
    }

    private func linked(_ state: AppState = AppState(values: Alex.allValues, cardLink: alexLink)) -> MemoryStore {
        MemoryStore(state)
    }

    private func sheet(_ reply: ExtensionResponse) throws -> PopupStateResponse {
        guard case .popupState(let body) = reply else { throw MessageError.malformed }
        return body
    }

    @Test func theNewestPinFromSafariWinsAndAnAppChangeAfterTheFoldStays() {
        let events = ExtensionEvents(pins: [
            PinEvent(host: site, kind: .email, valueID: Alex.schoolEmail.id, date: .daysAgo(2)),
            PinEvent(host: "www.\(site)", kind: .email, valueID: Alex.workEmail.id, date: .daysAgo(1))
        ])
        let folded = AppState().folding(events)
        #expect(folded.pins == [SitePin(host: site, kind: .email, valueID: Alex.workEmail.id)])
        #expect(folded.foldedThrough == .daysAgo(1))

        let unpinnedInApp = folded.pinning(nil, kind: .email, host: site)
        #expect(unpinnedInApp.folding(events).pins.isEmpty)
    }

    @Test func anUndoneSaveIsTurnedDownAndLeavesTheOrder() {
        let captured = Alex.value(.email("new.person@example.org"), label: nil, source: .captured)
        let state = AppState(values: Alex.emails + [captured])
        let undone = Capture(host: site, value: captured, date: .testNow, verdict: .dismissed)
        let events = ExtensionEvents(captures: [undone])
        let folded = state.folding(events)
        #expect(folded.rejectedValueIDs == [captured.id])
        #expect(folded.values == Alex.emails)
    }

    @Test func pickingAValueInSafariPutsItInTheFirstSlotRightAway() throws {
        let store = linked()
        let reply = try sheet(router(store).route([
            "type": "pin", "host": "shop.\(site)", "kind": "email", "valueID": Alex.workEmail.id.uuidString
        ]))
        #expect(gateway.card.emails.first?.payload.display == "alex@work.example.org")
        #expect(reply.kinds.first?.values.first?.text == "alex@work.example.org")
        #expect(reply.kinds.first?.pinnedID == Alex.workEmail.id)
        #expect(store.events.pins.map(\.host) == [site])
        #expect(store.events.cardWrites == [.testNow])

        let unpinned = try sheet(router(store).route(["type": "unpin", "host": site, "kind": "email"]))
        #expect(unpinned.kinds.first?.pinnedID == nil)
    }

    @Test func undoTakesACapturedValueOffTheCardAndNoFormSavesItAgain() throws {
        let store = linked()
        let router = router(store)
        let signup: [String: Any] = [
            "type": "capture", "host": site, "hasPassword": true, "trigger": "submit",
            "fields": [
                ["kind": "name", "userTyped": true, "value": "Alex Rivera", "autocomplete": "name"],
                ["kind": "email", "userTyped": true, "value": "new.person@example.org", "autocomplete": "email"]
            ]
        ]
        _ = router.route(signup)
        let added = try #require(store.events.captures.first?.value)
        #expect(try sheet(router.route(["type": "popupState", "host": site, "kinds": ["email"]])).recent.map(\.state)
            == [.saved])

        let reply = try sheet(router.route(["type": "undoCapture", "host": site, "valueID": added.id.uuidString]))
        #expect(!gateway.card.emails.map(\.key).contains(added.key))
        #expect(reply.recent.map(\.state) == [.removed])
        #expect(router.route(signup) == .capture(CaptureResponse(saved: 0, review: 0, ignored: 2)))
    }

    @Test func undoNeverRemovesAValueThePersonPutOnTheCard() throws {
        let store = linked()
        _ = try sheet(router(store).route([
            "type": "undoCapture", "host": site, "valueID": Alex.homeEmail.id.uuidString
        ]))
        #expect(gateway.card == Alex.card)
        #expect(store.events.captures.isEmpty)
    }

    @Test func aMutedSiteSavesNothing() throws {
        let store = linked()
        let router = router(store)
        #expect(try sheet(router.route(["type": "muteSite", "host": site, "muted": true])).muted)
        let signup: [String: Any] = [
            "type": "capture", "host": "www.\(site)", "hasPassword": false, "trigger": "submit",
            "fields": [["kind": "email", "userTyped": true, "value": "new.person@example.org"]]
        ]
        #expect(router.route(signup) == .capture(CaptureResponse(saved: 0, review: 0, ignored: 1)))
        #expect(store.events.captures.isEmpty)
    }

    @Test(arguments: [
        ["type": "popupState", "host": site, "kinds": ["email", "phone", "address", "email"]],
        ["type": "popupState", "host": site, "kinds": ["name"]],
        ["type": "pin", "host": "Site.example", "kind": "email", "valueID": UUID().uuidString],
        ["type": "pin", "host": site, "kind": "email", "valueID": "not-a-uuid"],
        ["type": "muteSite", "host": site, "muted": "yes"]
    ] as [[String: any Sendable]])
    func sheetRequestsBreakingTheRulesGetAnError(message: [String: any Sendable]) {
        #expect(router(linked()).route(message) == .error(reason: "unknown message"))
    }

    @Test func beforeSetUpTheSheetSaysSo() throws {
        let reply = try sheet(router(MemoryStore()).route(["type": "popupState", "host": site, "kinds": ["email"]]))
        #expect(reply == PopupStateResponse(status: .notSetUp))
        #expect(gateway.fetches == 0)
    }
}
