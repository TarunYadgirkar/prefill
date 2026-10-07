import Foundation
import Testing
@testable import PrefillKit

private let link = CardLink(
    contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
    original: Alex.card, snapshotAt: .daysAgo(30)
)

private let remembered = ExtensionResponse.picked(PickedResponse(remembered: true))
private let ignored = ExtensionResponse.picked(PickedResponse(remembered: false))

struct PickTests {
    private let gateway = FakeGateway()

    private func router(_ store: MemoryStore) -> MessageRouter {
        MessageRouter(store: store, gateway: gateway, now: { .testNow })
    }

    private func linked(_ settings: Settings = Settings(), events: ExtensionEvents = ExtensionEvents()) -> MemoryStore {
        MemoryStore(AppState(values: Alex.allValues, settings: settings, cardLink: link), events: events)
    }

    private func pick(_ kind: String, _ value: String, host: String = "boards.example.io") -> [String: Any] {
        ["type": "picked", "host": host, "kind": kind, "value": value]
    }

    private func emails(_ router: MessageRouter, host: String = "boards.example.io") -> [String] {
        suggested(router, host: host).map(\.value)
    }

    private func suggested(_ router: MessageRouter, host: String = "boards.example.io") -> [SuggestedValue] {
        let request: [String: Any] = ["type": "contactSuggestions", "host": host, "fields": [["kind": "email"]]]
        guard case .contactSuggestions(let reply) = router.route(request) else { return [] }
        return reply.emails
    }

    @Test func aPickComesFirstOnThatSiteWithoutWritingTheCard() {
        let store = linked()
        let router = router(store)
        #expect(emails(router).first != Alex.schoolEmail.display)
        #expect(router.route(pick("email", "ALEX.school@example.edu ")) == remembered)
        #expect(emails(router).first == Alex.schoolEmail.display)
        #expect(suggested(router).map(\.why) == [.pinned, .card, .card])
        #expect(emails(router, host: "elsewhere.example").first != Alex.schoolEmail.display)
        #expect(suggested(router, host: "elsewhere.example").allSatisfy { $0.why == .card })
        #expect(gateway.saves.isEmpty)
        #expect(store.events.pins.map(\.host) == ["example.io"])
        #expect(store.events.usage.map(\.valueID) == [Alex.schoolEmail.id])
    }

    @Test func aValueThePersonDoesntHaveIsntRemembered() {
        let store = linked()
        #expect(router(store).route(pick("email", "someone@else.example")) == ignored)
        #expect(store.events.pins.isEmpty)
    }

    @Test func pickingThePinnedValueAgainAddsNothing() {
        let store = linked()
        let router = router(store)
        _ = router.route(pick("phone", "(415) 555-0199"))
        _ = router.route(pick("phone", "+14155550199"))
        #expect(store.events.pins.count == 1)
    }

    @Test func anAddressIsPickedByItsStreetLine() {
        let store = linked()
        #expect(router(store).route(pick("address", "1 Market Street Suite 300")) == remembered)
        #expect(store.events.pins.first?.valueID == Alex.workAddress.id)
    }

    @Test func nothingIsRememberedWithMatchEachSiteOff() {
        let store = linked(Settings(matchEachSite: false))
        #expect(router(store).route(pick("email", Alex.schoolEmail.display)) == ignored)
        #expect(store.events.pins.isEmpty)
    }

    @Test func picksAreCappedPerMinute() {
        let busy = (0..<MessageRouter.maxPicksPerWindow).map { index in
            PinEvent(host: "site\(index).example", kind: .email, valueID: Alex.homeEmail.id, date: .testNow)
        }
        let store = linked(events: ExtensionEvents(pins: busy))
        #expect(router(store).route(pick("email", Alex.schoolEmail.display)) == ignored)
    }

    @Test func aPickedLinkComesFirstOnThatSite() {
        let card = Alex.card.replacing(.link, with: [
            CardEntry(label: nil, payload: .link("https://alexrivera.dev")),
            CardEntry(label: nil, payload: .link("https://alex.example.blog"))
        ])
        let gateway = FakeGateway(card: card)
        let router = MessageRouter(store: linked(), gateway: gateway, now: { .testNow })
        let ask: [String: Any] = ["type": "linkSuggestions", "host": "boards.example.io", "types": ["website"]]
        let urls = { () -> [String] in
            guard case .linkSuggestions(let reply) = router.route(ask) else { return [] }
            return reply.links.map { "\($0.url) \($0.why.rawValue)" }
        }
        #expect(urls() == ["https://alexrivera.dev card", "https://alex.example.blog card"])
        #expect(router.route(pick("link", "alex.example.blog")) == remembered)
        #expect(urls() == ["https://alex.example.blog pinned", "https://alexrivera.dev card"])
    }

    private func answers(_ router: MessageRouter, _ question: String) -> CustomSuggestionsResponse.Field? {
        let ask: [String: Any] = [
            "type": "customSuggestions", "host": "jobs.example.org", "fields": [["text": question]]
        ]
        guard case .customSuggestions(let reply) = router.route(ask) else { return nil }
        return reply.fields.first
    }

    private func customPick(_ value: String, question: String) -> [String: Any] {
        ["type": "picked", "host": "boards.example.io", "kind": "custom", "value": value, "question": question]
    }

    @Test func aPickedAnswerComesFirstForTheSameQuestionAnywhere() {
        let fields = [
            CustomField(label: "School", value: "UC Berkeley", matchWords: []),
            CustomField(label: "College", value: "Cal", matchWords: ["school"])
        ]
        let gateway = FakeGateway(card: Alex.card.replacingCustomFields(with: fields))
        let store = linked()
        let router = MessageRouter(store: store, gateway: gateway, now: { .testNow })
        #expect(answers(router, "School name")?.values.map(\.value) == ["UC Berkeley", "Cal"])
        #expect(router.route(customPick("Cal", question: "School name?")) == remembered)
        #expect(answers(router, "name, school")?.values.map(\.value) == ["Cal", "UC Berkeley"])
        #expect(router.route(customPick("Stanford", question: "School name")) == ignored)
        #expect(router.route(customPick("UC Berkeley", question: "the")) == ignored)
        #expect(router.route(customPick("", question: "School")) == ignored)
        #expect(store.events.answerPicks.count == 1)
        #expect(gateway.saves.isEmpty)
    }

    @Test func aPickedGuessAnswersAQuestionNothingMatched() {
        let fields = [CustomField(label: "School", value: "UC Berkeley", matchWords: [])]
        let gateway = FakeGateway(card: Alex.card.replacingCustomFields(with: fields))
        let router = MessageRouter(store: linked(), gateway: gateway, now: { .testNow })
        #expect(answers(router, "Alma mater")?.values.map(\.value) == [])
        #expect(router.route(customPick("UC Berkeley", question: "Alma mater")) == remembered)
        #expect(answers(router, "Alma mater")?.values.map(\.value) == ["UC Berkeley"])
    }
}
