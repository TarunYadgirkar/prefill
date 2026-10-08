import Foundation
import Synchronization
import Testing
@testable import PrefillKit

private let school = CustomField(label: "School", value: "UC Berkeley", matchWords: [])
private let usAuthorization = CustomField(label: "Work authorization (US)", value: "Yes", matchWords: [])
private let letter = CustomField(label: "Cover letter", value: "Dear team,\nHi.", matchWords: [], isDraft: true)

// Stands in for the on-device model: answers from a table and keeps what it was shown.
private final class FakeJudge: AnswerJudging {
    let replies: [String: AnswerVerdict]
    let asked = Mutex<[(AnswerQuestion, [AnswerCandidate])]>([])

    init(_ replies: [String: AnswerVerdict]) {
        self.replies = replies
    }

    func judge(_ question: AnswerQuestion, candidates: [AnswerCandidate]) async -> AnswerVerdict {
        asked.withLock { $0.append((question, candidates)) }
        return replies[question.text] ?? .unsure
    }
}

struct AnswerJudgeTests {
    @Test func theModelsReplyIsHeldToTheCandidatesAndTheirScope() {
        let candidates = AnswerCandidate.from([school, usAuthorization])
        let ask = { (text: String, verdict: String, name: String) in
            AnswerVerdict.checked(
                verdict: verdict, name: name, question: AnswerQuestion(text: text), candidates: candidates
            )
        }
        #expect(ask("Where do you study?", "use", "school") == .use(label: "School"))
        #expect(ask("Where do you study?", "use", "Employer") == .unsure)
        #expect(ask("Can you work in Canada?", "use", "Work authorization (US)") == .needsNew)
        #expect(ask("Favourite colour", "needsNew", "none") == .needsNew)
        #expect(ask("Favourite colour", "maybe", "School") == .unsure)
    }

    // The app's background pass: the model sees the question with its heading and options and
    // every answer but drafts, and only `use` reaches the page, as a guess.
    @Test func onlyUseIsOfferedAndOnlyForTheAnswersItWasJudgedAgainst() async throws {
        let fields = [school, usAuthorization, letter]
        let questions = [
            FormQuestion(host: "example.com", text: "Alma mater", date: .testNow, heading: "Education", options: ["A"]),
            FormQuestion(host: "example.com", text: "Favourite colour", date: .testNow)
        ]
        let judge = FakeJudge(["Alma mater": .use(label: "School"), "Favourite colour": .needsNew])
        let cached = await AnswerGuessing.ask(questions, fields: fields, judge: judge, variant: "v")
        let seen = judge.asked.withLock { $0 }
        #expect(seen.first?.0 == AnswerQuestion(text: "Alma mater", heading: "Education", options: ["A"]))
        #expect(seen.first?.1.map(\.label) == ["School", "Work authorization (US)"])

        let state = AppState().recording(cached, siteKinds: [:])
        #expect(state.guessedAnswer(for: "Alma mater", in: fields, variant: "v") == school)
        #expect(state.guessedAnswer(for: "Favourite colour", in: fields, variant: "v") == nil)
        let edited = [CustomField(label: "School", value: "Stanford", matchWords: []), usAuthorization, letter]
        #expect(state.guessedAnswer(for: "Alma mater", in: edited, variant: "v") == nil)
        #expect(AnswerRevision.of(fields) == AnswerRevision.of(fields.reversed()))
    }

    @Test func theHandlerKeepsTheHeadingAndOptionsWithAQuestionForTheApp() throws {
        let card = Alex.card.replacingCustomFields(with: [school])
        let link = CardLink(
            contactIdentifier: card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        let router = MessageRouter(store: store, gateway: FakeGateway(card: card), now: { .testNow })
        _ = router.route([
            "type": "customSuggestions", "host": "jobs.example.com",
            "fields": [["text": "Pronunciation of your name", "heading": "About you", "options": ["Yes", "No"]]]
        ])
        #expect(try store.readEvents().questions == [FormQuestion(
            host: "example.com", text: "Pronunciation of your name", date: .testNow, heading: "About you",
            options: ["Yes", "No"]
        )])
    }

    @Test func theMacPanelSuggestsOnlyWhatTheModelSaysToUse() async {
        let judge = FakeJudge(["Alma mater": .use(label: "School"), "Visa": .use(label: "Cover letter")])
        let fields = [school, letter]
        #expect(await AnswerGuessing.suggestion(for: AnswerQuestion(text: "Alma mater"), fields: fields, judge: judge)
            == school)
        #expect(await AnswerGuessing.suggestion(for: AnswerQuestion(text: "Visa"), fields: fields, judge: judge) == nil)
    }
}
