import Foundation
import Testing
@testable import PrefillKit

// Questions as real forms word them (web/src/fixtures: Garner and Braeburn on Greenhouse,
// Rover and Kepler on Lever, Decagon on Ashby).
struct ScopeTests {
    private static let work: Set<AnswerScope.Kind> = [.country, .term]

    @Test(arguments: [
        ("Are you legally authorized to work in the United States of America?", "US"),
        ("Are you legally authorized to work in the United States?", "US"),
        ("Do you or will you require sponsorship in the future to work in the U.S.?", "US"),
        (
            "Will you now or in the future require sponsorship for employment visa status (e.g., H-1B visa status)?",
            "US"
        ),
        (
            "Are you legally able to work in Canada according to the laws and regulations of the province "
                + "or territory where you live?", "Canada"
        ),
        ("Are you authorized to work in the UK?", "UK"),
        ("Will you require sponsorship for a Summer 2026 internship?", "Summer 2026"),
        ("Are you presently authorized to work for Braeburn in the position for which you are applying?", nil),
        (
            "Will you now or in the future require Braeburn to sponsor you or to obtain, maintain or extend "
                + "your employment authorization?", nil
        ),
        ("How did you hear about us?", nil),
        ("Are you authorized to work in the US or Canada?", nil)
    ] as [(String, String?)])
    func aQuestionsScopeComesFromItsWords(text: String, scope: String?) {
        #expect(AnswerScope.find(in: text, kinds: Self.work)?.name == scope)
    }

    @Test func onlyTheKindsAQuestionDependsOnCount() {
        #expect(AnswerScope.find(in: "What school do you attend in the United States?", kinds: []) == nil)
        #expect(AnswerScope.find(in: "GPA as of autumn 2025", kinds: [.term])?.name == "Fall 2025")
        #expect(JobQuestion.school.scopeKinds.isEmpty)
    }

    @Test func aLabelCarriesItsScope() {
        #expect(AnswerScope.split("Work authorization (US)").base == "Work authorization")
        #expect(AnswerScope.split("Work authorization (US)").scope == AnswerScope(kind: .country, name: "US"))
        #expect(AnswerScope.split("GPA (Fall 2025)").scope?.kind == .term)
        #expect(AnswerScope.split("Phone (work)").base == "Phone (work)")
        #expect(AnswerScope.split("Sponsorship").scope == nil)
    }

    @Test func scopesFillClashOrAreOnlyOffered() {
        let usa = AnswerScope(kind: .country, name: "US")
        let canada = AnswerScope(kind: .country, name: "Canada")
        let summer = AnswerScope(kind: .term, name: "Summer 2026")
        #expect(ScopeFit(answer: nil, asked: nil) == .same)
        #expect(ScopeFit(answer: usa, asked: usa) == .same)
        #expect(ScopeFit(answer: usa, asked: canada) == .clash)
        #expect(ScopeFit(answer: nil, asked: canada) == .other)
        #expect(ScopeFit(answer: usa, asked: nil) == .other)
        #expect(ScopeFit(answer: usa, asked: summer) == .other)
    }

    @Test func optionsAndTheQuestionStayWithinTheLimits() throws {
        let answer = { (extra: [String: Any]) -> [String: Any] in
            ["type": "answers", "host": "jobs.example.com", "action": "learn",
             "answers": [["question": "sponsorship", "value": "No"].merging(extra) { $1 }]]
        }
        let failure = { (message: [String: Any]) -> String? in
            do {
                _ = try MessageCoding.request(from: message)
                return nil
            } catch { return MessageCoding.failureName(error) }
        }
        let tenOptions = Array(repeating: String(repeating: "o", count: 100), count: 10)
        #expect(failure(answer(["text": String(repeating: "q", count: 200), "options": tenOptions])) == nil)
        #expect(failure(answer(["text": String(repeating: "q", count: 201)])) == "tooLarge")
        #expect(failure(answer(["options": tenOptions + ["one more"]])) == "tooLarge")
        #expect(failure(answer(["options": [String(repeating: "o", count: 101)]])) == "tooLarge")
        #expect(failure(answer(["text": "Work in\u{202E} Canada?"])) == "malformed")
        #expect(failure(answer(["options": ["Yes\u{200B}"]])) == "malformed")
    }
}

struct ScopedAnswerTests {
    private let gateway = FakeGateway(card: Alex.card)
    private static let usText = "Are you legally authorized to work in the United States?"
    private static let canadaText = "Are you legally able to work in Canada according to the laws of your province?"

    private func router() -> MessageRouter {
        let link = CardLink(
            contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: Alex.card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        return MessageRouter(store: store, gateway: gateway, now: { .testNow })
    }

    private func learn(_ value: String, _ text: String?, host: String = "jobs.lever.co") -> AnswersRequest {
        AnswersRequest(host: host, action: .learn, answers: [
            .init(question: .authorization, value: value, text: text, options: ["Yes", "No"])
        ])
    }

    private func asked(_ router: MessageRouter, _ text: String) -> CustomSuggestionsResponse.Field? {
        router.customSuggestions(CustomSuggestionsRequest(host: "boards.example.io", fields: [.init(text: text)]))
            .fields.first
    }

    @Test func eachCountryGetsItsOwnAnswerAndNeitherReplacesTheOther() {
        let router = router()
        #expect(router.answers(learn("Yes", Self.usText)) == AnswersResponse(saved: 1))
        #expect(router.answers(learn("No", Self.canadaText, host: "jobs.example.ca")) == AnswersResponse(saved: 1))
        #expect(gateway.card.customFields.map(\.label) == ["Work authorization (US)", "Work authorization (Canada)"])
        #expect(gateway.card.customFields.map(\.value) == ["Yes", "No"])
    }

    @Test func aLaterAnswerReplacesOnlyTheOneForTheSameScope() {
        let router = router()
        _ = router.answers(learn("Yes", Self.usText))
        _ = router.answers(learn("Yes", Self.canadaText))
        let changed = router.answers(learn("No", "Are you authorized to work in the U.S.?"))
        #expect(changed == AnswersResponse(saved: 0, updated: ["Work authorization (US)"]))
        #expect(gateway.card.customFields.map(\.value) == ["No", "Yes"])
        #expect(router.answers(AnswersRequest(host: "jobs.lever.co", action: .undo)).saved == 2)
        #expect(gateway.card.customFields.map(\.value) == ["Yes"])
    }

    @Test func aQuestionKeepsAnswersForAtMostThreeScopes() {
        let router = router()
        for country in ["United States", "Canada", "UK", "Germany"] {
            let question = "Are you legally authorized to work in \(country)?"
            _ = router.answers(learn("Yes", question, host: "\(country.count).example"))
        }
        #expect(gateway.card.customFields.map(\.label) == [
            "Work authorization (US)", "Work authorization (Canada)", "Work authorization (UK)"
        ])
    }

    @Test func aQuestionWithNoScopeKeepsTodaysLabel() {
        let router = router()
        _ = router.answers(learn("Yes", "Are you presently authorized to work for Braeburn in the position?"))
        _ = router.answers(learn("No", nil, host: "old.example.com"))
        #expect(gateway.card.customFields.map(\.label) == ["Work authorization"])
    }

    @Test func aCanadaQuestionNeverGetsTheUSAnswer() {
        let router = router()
        _ = router.answers(learn("Yes", Self.usText))
        let canada = asked(router, Self.canadaText)
        #expect(canada?.values.isEmpty == true)
        #expect(canada?.suggested.isEmpty == true)
        #expect(canada?.guesses.isEmpty == true)
        #expect(canada?.noAnswerFor == "Canada")
        #expect(asked(router, Self.usText)?.values.map(\.value) == ["Yes"])
    }

    @Test func anAnswerWithoutAScopeIsOfferedButNotFilledWhereOneIsAsked() {
        let router = router()
        _ = router.answers(learn("Yes", "Are you authorized to work in the position you're applying for?"))
        let usa = asked(router, Self.usText)
        #expect(usa?.values.isEmpty == true)
        #expect(usa?.suggested.map(\.value) == ["Yes"])
        #expect(usa?.suggested.first?.label == "Work authorization")
        #expect(usa?.noAnswerFor == nil)
        #expect(asked(router, "Are you authorized to work for Braeburn?")?.values.map(\.value) == ["Yes"])
    }

    @Test func aScopedAnswerIsOnlyOfferedWhereNoScopeIsAsked() {
        let router = router()
        _ = router.answers(learn("Yes", Self.usText))
        let open = asked(router, "Are you authorized to work for Braeburn?")
        #expect(open?.values.isEmpty == true)
        #expect(open?.suggested.map(\.label) == ["Work authorization (US)"])
    }

    @Test func aPickCantBringBackAnAnswerWithheldForItsScope() throws {
        let link = CardLink(
            contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: Alex.card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        let router = MessageRouter(store: store, gateway: gateway, now: { .testNow })
        _ = router.answers(learn("Yes", Self.usText))
        let pick = PickedRequest(host: "jobs.example.ca", kind: .custom, value: "Yes", question: Self.canadaText)
        _ = router.picked(pick)
        #expect(asked(router, Self.canadaText)?.values.isEmpty == true)
    }
}
