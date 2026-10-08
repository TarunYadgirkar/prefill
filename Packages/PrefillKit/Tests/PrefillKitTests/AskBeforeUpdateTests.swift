import Foundation
import Testing
@testable import PrefillKit

// The person changed an answer Prefill filled, then submitted: nothing changes until they
// choose "Update everywhere" (the usual replace, with its guards) or "Just here".
struct AskBeforeUpdateTests {
    private let gateway = FakeGateway(card: Alex.card)

    private func router() -> (MessageRouter, MemoryStore) {
        let link = CardLink(
            contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: Alex.card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        return (MessageRouter(store: store, gateway: gateway, now: { .testNow }), store)
    }

    private func request(_ action: AnswersRequest.Action, _ school: String, changed: Bool = true) -> AnswersRequest {
        AnswersRequest(host: "jobs.lever.co", action: action, answers: [
            .init(question: .school, value: school, changedFill: changed)
        ])
    }

    @Test func aChangedFillIsHeldBackAndUpdateEverywhereReplacesIt() throws {
        let (router, store) = router()
        _ = router.answers(request(.learn, "UC Berkeley", changed: false))
        #expect(router.answers(request(.learn, "Stanford")) == AnswersResponse(saved: 0, ask: ["School"]))
        #expect(gateway.card.customFields.map(\.value) == ["UC Berkeley"])
        #expect(router.answers(request(.update, "Stanford")) == AnswersResponse(saved: 0, updated: ["School"]))
        #expect(gateway.card.customFields.map(\.value) == ["Stanford"])
        // Undo works as for any replacement.
        _ = router.answers(AnswersRequest(host: "jobs.lever.co", action: .undo))
        #expect(gateway.card.customFields.map(\.value) == ["UC Berkeley"])
        #expect(try store.readEvents().overrides.isEmpty)
    }

    @Test func justHereKeepsTheCardAndIsOfferedOnThatSiteOnly() throws {
        let (router, store) = router()
        _ = router.answers(request(.learn, "UC Berkeley", changed: false))
        #expect(router.answers(request(.keepHere, "Berkeley")) == AnswersResponse(saved: 1))
        #expect(gateway.card.customFields.map(\.value) == ["UC Berkeley"])
        #expect(try store.readEvents().overrides.map(\.value) == ["Berkeley"])
        // The same change on that site isn't asked about again.
        #expect(router.answers(request(.learn, "Berkeley")) == AnswersResponse(saved: 0))

        let ask = { (host: String) in
            router.route(["type": "customSuggestions", "host": host, "fields": [["text": "School"]]])
        }
        guard case .customSuggestions(let here) = ask("jobs.lever.co"),
              case .customSuggestions(let elsewhere) = ask("boards.greenhouse.io") else {
            Issue.record("expected customSuggestions")
            return
        }
        #expect(here.fields.first?.values.map(\.value) == ["UC Berkeley"])
        #expect(here.fields.first?.suggested == [SuggestedValue(value: "Berkeley", why: .used, label: "School")])
        #expect(elsewhere.fields.first?.suggested.isEmpty == true)
    }

    @Test func justHereNeedsALearnedAnswerThePersonChangedAfterAFill() {
        let (router, _) = router()
        #expect(router.answers(request(.keepHere, "Berkeley")) == AnswersResponse(saved: 0))
        _ = router.answers(request(.learn, "UC Berkeley", changed: false))
        #expect(router.answers(request(.keepHere, "Berkeley", changed: false)) == AnswersResponse(saved: 0))
    }
}
