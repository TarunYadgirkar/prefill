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

    private let stanford = AnswersRequest(host: "jobs.example.com", action: .learn, answers: [
        .init(question: .school, value: "Stanford University")
    ])

    @Test func aSubmittedApplicationsAnswersBecomeCustomFieldsOnce() throws {
        let (router, store) = router()
        #expect(router.answers(applied) == AnswersResponse(saved: 3))
        #expect(gateway.card.customFields.map(\.label) == ["School", "Sponsorship", "How did you hear about us"])
        #expect(try store.readEvents().answers.map(\.value) == applied.answers.map(\.value))
        #expect(router.answers(applied) == AnswersResponse(saved: 0))
        #expect(gateway.card.customFields.count == 3)
    }

    @Test func aLaterAnswerReplacesALearnedOneAndUndoPutsItBack() throws {
        let (router, store) = router()
        _ = router.answers(applied)
        #expect(router.answers(stanford) == AnswersResponse(saved: 0, updated: 1))
        #expect(gateway.card.customFields.first?.value == "Stanford University")
        #expect(try store.readEvents().answers.last?.previous == "University of California, Berkeley")
        #expect(router.answers(AnswersRequest(host: "jobs.example.com", action: .undo)) == AnswersResponse(saved: 1))
        #expect(gateway.card.customFields.map(\.value) == applied.answers.map(\.value))
    }

    @Test func anAnswerThePersonWroteIsNeverReplaced() throws {
        let school = try #require(JobQuestion.school.field(answer: "UC Berkeley"))
        gateway.state.withLock { $0.card = Alex.card.replacingCustomFields(with: [school]) }
        let (router, _) = router()
        #expect(router.answers(stanford) == AnswersResponse(saved: 0))
        #expect(gateway.card.customFields == [school])
    }

    @Test func aLearnedAnswerFillsTheNextApplicationsQuestion() {
        let (router, _) = router()
        _ = router.answers(applied)
        let asked = CustomSuggestionsRequest(host: "jobs.example.com", fields: [
            .init(text: "Will you now or in the future require sponsorship?"), .init(text: "University")
        ])
        #expect(router.customSuggestions(asked).fields.map { $0.values.map(\.value) } == [
            ["No"], ["University of California, Berkeley"]
        ])
        let school = SuggestedValue(
            value: "University of California, Berkeley", why: .learned, label: "School", site: "example.io"
        )
        #expect(router.customSuggestions(asked).fields.last?.values == [school])
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

    @Test func pagesTogetherCantAddMoreThanOneApplicationsWorthADay() throws {
        let (router, store) = router()
        let earlier = (0..<8).map { LearnedAnswer(host: "a.example", label: "Q\($0)", value: "x", date: .testNow) }
        try store.appendEvents(ExtensionEvents(answers: earlier))
        #expect(router.answers(applied).saved == 0)
        #expect(gateway.card.customFields.isEmpty)
    }

    @Test func addingAnswersMayOnlyAppendCustomFields() throws {
        let school = try #require(JobQuestion.school.field(answer: "UC Berkeley"))
        let major = try #require(JobQuestion.major.field(answer: "EECS"))
        let basis = Alex.card.replacingCustomFields(with: [school])
        #expect(CardSaveScope.addAnswers.allows(basis.replacingCustomFields(with: [school, major]), over: basis))
        #expect(!CardSaveScope.addAnswers.allows(basis.replacingCustomFields(with: [major]), over: basis))
        #expect(!CardSaveScope.keepEveryValue.allows(basis.replacingCustomFields(with: [school, major]), over: basis))
        #expect(!CardSaveScope.addAnswers.allows(basis.replacing(.email, with: []), over: basis))
    }

    @Test func theStudentStarterAddsOnlyFilledInAnswersForQuestionsWithoutOne() throws {
        #expect(StudentStarter.answers[.school] == "University of California, Berkeley")
        let major = try #require(JobQuestion.major.field(answer: "EECS"))
        let typed = StudentStarter.answers.merging([.major: "Data Science", .gpa: " 3.9 ", .degree: ""]) { $1 }
        let added = StudentStarter.fields(for: typed, adding: [major])
        #expect(added.map(\.label) == ["School", "GPA"])
        #expect(added.map(\.value) == ["University of California, Berkeley", "3.9"])
        #expect(StudentStarter.missing(from: [major] + added) == [.degree, .graduation])
    }
}
