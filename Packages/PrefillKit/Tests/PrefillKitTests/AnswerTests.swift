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
        #expect(router.answers(stanford) == AnswersResponse(saved: 0, updated: ["School"]))
        #expect(gateway.card.customFields.first?.value == "Stanford University")
        #expect(try store.readEvents().answers.last?.previous == "University of California, Berkeley")
        #expect(router.answers(AnswersRequest(host: "jobs.example.com", action: .undo)) == AnswersResponse(saved: 1))
        #expect(gateway.card.customFields.map(\.value) == applied.answers.map(\.value))
    }

    @Test func aLearnedAnswerSaysItsSiteOnlyWhenThePageCanTakeIt() {
        let field = CustomField(label: "School", value: "UC Berkeley", matchWords: [])
        let learned = { (host: String) in
            MessageRouter.sourced(["UC Berkeley"], from: [field], learned: [
                LearnedAnswer(host: host, label: "School", value: "UC Berkeley", date: .testNow)
            ]).first
        }
        #expect(learned("example.io")?.site == "example.io")
        #expect(learned("Bücher.example")?.site == nil)
        #expect(learned("Bücher.example")?.why == .learned)
        #expect(SuggestedValue(value: "x", why: .card, site: "example.io").site == nil)
    }

    @Test func aLabelWithHiddenCharactersGoesOutPlain() {
        let field = CustomField(label: "Sch\u{200B}ool\u{202E}", value: "UC Berkeley", matchWords: [])
        let hidden = CustomField(label: "\u{200B}", value: "Cal", matchWords: [])
        let sent = MessageRouter.sourced(["UC Berkeley", "Cal"], from: [field, hidden], learned: [])
        #expect(sent.map(\.label) == ["Sch ool ", nil])
    }

    @Test func aValueTwoFieldsShareTakesTheLabelOfTheFieldThatMatched() {
        let fields = [
            CustomField(label: "School", value: "UC Berkeley", matchWords: []),
            CustomField(label: "College", value: "UC Berkeley", matchWords: [])
        ]
        gateway.state.withLock { $0.card = Alex.card.replacingCustomFields(with: fields) }
        let (router, _) = router()
        let asked = CustomSuggestionsRequest(
            host: "jobs.example.com", fields: [.init(text: "College"), .init(text: "School")]
        )
        #expect(router.customSuggestions(asked).fields.map { $0.values.first?.label } == ["College", "School"])
    }

    @Test func eachLearnedAnswerIsReplacedAtMostOnceADay() {
        let (router, _) = router()
        _ = router.answers(applied)
        #expect(router.answers(stanford).updated == ["School"])
        let again = AnswersRequest(host: "evil.example", action: .learn, answers: [
            .init(question: .school, value: "Nowhere College"), .init(question: .sponsorship, value: "Yes")
        ])
        #expect(router.answers(again) == AnswersResponse(saved: 0, updated: ["Sponsorship"]))
        #expect(gateway.card.customFields.first?.value == "Stanford University")
    }

    @Test func replacingAnswersMayChangeOnlyTheLearnedValues() throws {
        let school = try #require(JobQuestion.school.field(answer: "UC Berkeley"))
        let major = try #require(JobQuestion.major.field(answer: "EECS"))
        let basis = Alex.card.replacingCustomFields(with: [school, major])
        let scope = CardSaveScope.replaceAnswers([school.id])
        let stanford = CustomField(label: school.label, value: "Stanford", matchWords: school.matchWords)
        let math = CustomField(label: major.label, value: "Math", matchWords: major.matchWords)
        #expect(scope.allows(basis.replacingCustomFields(with: [stanford, major]), over: basis))
        #expect(!scope.allows(basis.replacingCustomFields(with: [school, math]), over: basis))
        #expect(!scope.allows(basis.replacingCustomFields(with: [stanford]), over: basis))
        #expect(!scope.allows(basis.replacingCustomFields(with: [major, stanford]), over: basis))
        let changed = basis.replacingCustomFields(with: [stanford, major])
        #expect(!scope.allows(changed.replacing(.email, with: Array(changed.emails.dropFirst())), over: basis))
        let extra = CardEntry(label: nil, payload: .email("new@example.net"))
        #expect(!scope.allows(changed.replacing(.email, with: changed.emails + [extra]), over: basis))
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
