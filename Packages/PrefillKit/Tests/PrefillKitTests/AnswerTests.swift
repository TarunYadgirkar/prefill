import Foundation
import Testing
@testable import PrefillKit

struct AnswerTests {
    private let gateway = FakeGateway(card: Alex.card)

    private func router(at date: Date = .testNow) -> (MessageRouter, MemoryStore) {
        let link = CardLink(
            contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: Alex.card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        return (MessageRouter(store: store, gateway: gateway, now: { date }), store)
    }

    private let applied = AnswersRequest(host: "boards.example.io", action: .learn, answers: [
        .init(question: .school, value: "University of California, Berkeley"),
        .init(question: .sponsorship, value: "No"),
        .init(question: .heard, value: "LinkedIn")
    ])

    @Test func aSubmittedApplicationsAnswersBecomeCustomFieldsOnce() throws {
        let (router, store) = router()
        #expect(router.answers(applied) == AnswersResponse(saved: 3))
        #expect(gateway.card.customFields.map(\.label) == ["School", "Sponsorship", "How did you hear about us"])
        #expect(try store.readEvents().answers.map(\.value) == applied.answers.map(\.value))
        let again = AnswersRequest(host: "jobs.example.com", action: .learn, answers: [
            .init(question: .school, value: "Stanford University")
        ])
        #expect(router.answers(again) == AnswersResponse(saved: 0))
        #expect(gateway.card.customFields.first?.value == "University of California, Berkeley")
    }

    @Test func aLearnedAnswerFillsTheNextApplicationsQuestion() {
        let (router, _) = router()
        _ = router.answers(applied)
        let asked = CustomSuggestionsRequest(host: "jobs.example.com", fields: [
            .init(text: "Will you now or in the future require sponsorship?"), .init(text: "University")
        ])
        #expect(router.customSuggestions(asked).fields.map(\.values) == [
            ["No"], ["University of California, Berkeley"]
        ])
    }

    @Test func undoTakesBackOnlyWhatTheSiteJustAdded() {
        let (router, _) = router()
        _ = router.answers(applied)
        let undo = AnswersRequest(host: "boards.example.io", action: .undo)
        #expect(router.answers(AnswersRequest(host: "other.example.com", action: .undo)).saved == 0)
        #expect(router.answers(undo) == AnswersResponse(saved: 3))
        #expect(gateway.card.customFields.isEmpty)
        #expect(gateway.card.emails == Alex.card.emails)
    }
}
