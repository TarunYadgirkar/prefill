import Foundation
import Testing
@testable import PrefillKit

struct AnswerOfferTests {
    private struct Judge: OfferJudging {
        func reusableLabel(question: String, answer: String) async -> String? {
            question.contains("Python") ? "Python experience" : nil
        }
    }

    private func application(_ fields: [(String, String)], daysAgo: Double = 1) -> SubmittedApplication {
        let request = ApplicationRequest(
            host: "boards.greenhouse.io", path: "/acme/jobs/1", title: "Intern at Acme",
            fields: fields.map { ApplicationRequest.Field(question: $0.0, answer: $0.1) }, files: []
        )
        return SubmittedApplication(date: .daysAgo(daysAgo), request: request)
    }

    private let sent: [(String, String)] = [
        ("Email", "alex@example.com"),
        ("Which university do you attend?", "UC Berkeley"),
        ("Will you require sponsorship to work in Canada?", "No"),
        ("Gender", "Male"),
        ("Years of experience with Python", "3"),
        ("Why do you want to work at Acme?", "I love rockets")
    ]

    private func source(
        _ applications: [SubmittedApplication], fields: [CustomField] = [], state: AppState = AppState()
    ) -> AnswerOffers.Source {
        AnswerOffers.Source(applications: applications, fields: fields, state: state, variant: "m", now: .testNow)
    }

    @Test func theRulesOfferTheKnownQuestionsAndNothingIsSavedByItself() {
        let offers = AnswerOffers.offers(source([application(sent)]))
        #expect(offers.map(\.field.label) == ["School", "Sponsorship (Canada)"])
        #expect(offers.map(\.field.value) == ["UC Berkeley", "No"])
    }

    @Test func theModelNamesAReusableAnswerOnceAndAOneOffIsNeverOffered() async {
        let applications = [application(sent)]
        let verdicts = await AnswerOffers.ask(source(applications), judge: Judge())
        #expect(verdicts.map(\.answer) == ["Python experience", "no"])
        let state = AppState().recording(verdicts, siteKinds: [:])
        let offers = AnswerOffers.offers(source(applications, state: state))
        #expect(offers.map(\.field.label) == ["School", "Sponsorship (Canada)", "Python experience"])
        #expect(await AnswerOffers.ask(source(applications, state: state), judge: Judge()).isEmpty)
    }

    @Test func aSavedOrDismissedAnswerAndAnOldApplicationOfferNothing() throws {
        let applications = [application(sent)]
        let school = try #require(JobQuestion.school.field(answer: "Stanford"))
        let saved = AnswerOffers.offers(source(applications, fields: [school]))
        #expect(saved.map(\.field.label) == ["Sponsorship (Canada)"])
        let dismissed = AppState().dismissing(saved[0])
        #expect(AnswerOffers.offers(source(applications, fields: [school], state: dismissed)).isEmpty)
        #expect(AnswerOffers.offers(source([application(sent, daysAgo: 30)])).isEmpty)
    }
}
