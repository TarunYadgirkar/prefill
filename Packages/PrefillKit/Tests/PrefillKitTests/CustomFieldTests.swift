import Contacts
import Testing
@testable import PrefillKit

private func field(_ label: String, _ value: String, also: String = "") -> CustomField {
    (try? CustomField.make(label: label, value: value, alsoMatches: also).get())!
}

private let school = field("School", "UC Berkeley", also: "university, college")
private let major = field("Major", "EECS", also: "field of study, discipline")
private let graduation = field("Graduation year", "2028")
private let heard = field("How did you hear about us", "LinkedIn", also: "referral source")
private let fields = [school, major, graduation, heard]

struct CustomFieldTests {
    // Labels, names and placeholders as Greenhouse, Lever and Workday write them.
    @Test(arguments: [
        ("School *", ["UC Berkeley"]),
        ("University job_application[educations][0][school_name_id]", ["UC Berkeley"]),
        ("Field of Study educationSection.fieldOfStudy", ["EECS"]),
        ("Discipline", ["EECS"]),
        ("Expected graduation year", ["2028"]),
        ("How did you hear about this job? job_application[answers_attributes][2][text_value]", ["LinkedIn"]),
        ("Referral source cards[a1b2][field3]", ["LinkedIn"]),
        ("Year of birth", []),
        ("Current company", []),
        ("Website", [])
    ])
    func offersTheFieldAJobApplicationAsksFor(text: String, expected: [String]) {
        #expect(CustomFieldMatcher.values(for: text, in: fields) == expected)
    }

    // Questions from web/src/fixtures: tally-hackhub.html and ats-lever-zoox.html.
    @Test func aQuestionThatOnlyMentionsAWordDoesntGetTheAnswer() {
        let sponsorship = field("Sponsorship", "No", also: "sponsor, visa")
        let all = fields + [sponsorship]
        let promote = "How do you plan to promote hackathons at your university?"
        #expect(CustomFieldMatcher.values(for: promote, in: all) == [])
        #expect(CustomFieldMatcher.values(for: "University Name Enter your university", in: all) == ["UC Berkeley"])
        #expect(CustomFieldMatcher.values(for: "Name of the college you attend", in: all) == ["UC Berkeley"])
        #expect(CustomFieldMatcher.values(
            for: "Do you currently receive any active funding (e.g., grants, sponsorships)?", in: all
        ) == [])
        #expect(CustomFieldMatcher.values(
            for: "Will you now or in the future require sponsorship for employment visa status (e.g., H-1B)?", in: all
        ) == ["No"])
    }

    // Questions from web/src/fixtures/ats-lever-veeva.html and the Lever and Greenhouse fixtures.
    @Test func sponsorshipAndAuthorizationAnswersStayWithTheirOwnQuestions() {
        let authorization = field(
            "Work authorization", "Yes", also: "authorized to work, legally authorized, eligible to work"
        )
        let sponsorship = field("Sponsorship", "No", also: "sponsor, visa")
        let both = [authorization, sponsorship]
        #expect(CustomFieldMatcher.values(
            for: "Will you now or in the future require sponsorship for work authorization?", in: both
        ) == ["No"])
        let authorized = "Are you legally authorized to work in the United States?"
        #expect(CustomFieldMatcher.values(for: authorized, in: both) == ["Yes"])
        #expect(CustomFieldMatcher.values(
            for: "Are you authorized to work in the US without the need for visa sponsorship?", in: both
        ) == [])
    }

    @Test func offersEveryFieldThatTiesInTheCardsOrder() {
        let college = field("College", "Diablo Valley College")
        #expect(CustomFieldMatcher.values(for: "College or university", in: [school, college]) == [
            "UC Berkeley", "Diablo Valley College"
        ])
    }

    @Test func theCardLabelRoundTripsAndLeavesRealRelatedNamesAlone() {
        #expect(CustomFieldLabel.encode(school) == "School · Prefill · university, college")
        #expect(CustomFieldLabel.encode(graduation) == "Graduation year · Prefill")
        #expect(CustomFieldLabel.decode(label: CustomFieldLabel.encode(school), value: "UC Berkeley") == school)
        #expect(CustomFieldLabel.decode(label: CNLabelContactRelationSpouse, value: "Sam") == nil)
        #expect(CustomFieldLabel.decode(label: "School · Other", value: "UC Berkeley") == nil)
    }

    @Test func checksWhatThePersonTyped() {
        let trimmed = field(" School ", " UC Berkeley ", also: "university, , college ")
        #expect(trimmed.matchWords == ["university", "college"])
        #expect((try? CustomField.make(label: "School · 2", value: "x", alsoMatches: "").get()) == nil)
        #expect((try? CustomField.make(label: "", value: "x", alsoMatches: "").get()) == nil)
        #expect((try? [school].saving(field("school", "Stanford"), replacing: nil).get()) == nil)
        let replaced = try? [school].saving(field("school", "Stanford"), replacing: school).get()
        #expect(replaced?.first?.value == "Stanford")
    }

    @Test func cardRewritesKeepCustomFieldsAndOtherRelatedNames() {
        let contact = CNMutableContact()
        let spouse = CNLabeledValue(label: CNLabelContactRelationSpouse, value: CNContactRelation(name: "Sam"))
        contact.contactRelations = [spouse]
        let card = CNCardMapping.record(from: contact, identifier: "alex-card")
        CNCardMapping.apply(card.replacingCustomFields(with: [school, major]), to: contact)
        #expect(contact.contactRelations.first?.identifier == spouse.identifier)
        #expect(CNCardMapping.record(from: contact, identifier: "alex-card").customFields == [school, major])

        let withFields = CNCardMapping.record(from: contact, identifier: "alex-card")
        let reordered = withFields.replacing(.email, with: [Alex.workEmail.entry])
        #expect(reordered.keepsEveryValue(of: withFields))
        #expect(withFields.replacingCustomFields(with: []).keepsEveryValue(of: withFields) == false)
        let emptied = withFields.replacingCustomFields(with: [])
        #expect(emptied.restoringValues(of: withFields).customFields == [school, major])
    }

    @Test func pagesGetMatchingValuesFromTheCard() {
        let card = Alex.card.replacingCustomFields(with: fields)
        let link = CardLink(
            contactIdentifier: card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: .daysAgo(30)
        )
        let router = MessageRouter(
            store: MemoryStore(AppState(values: Alex.allValues, cardLink: link)), gateway: FakeGateway(card: card),
            now: { .testNow }
        )
        let reply = router.route([
            "type": "customSuggestions", "host": "boards.example.io",
            "fields": [["text": "School"], ["text": "Cover letter"]]
        ])
        let expected = CustomSuggestionsResponse(fields: [
            .init(values: [SuggestedValue(value: "UC Berkeley", label: "School")]), .init(values: [])
        ])
        #expect(reply == .customSuggestions(expected))
    }

    // The model's answer, cached by the app, reaches the field as a marked guess; a question
    // nobody has asked about yet is kept for the app, once, with only its words.
    @Test func aCachedGuessIsOfferedAndANewQuestionIsNotedForTheApp() throws {
        let card = Alex.card.replacingCustomFields(with: fields)
        let link = CardLink(
            contactIdentifier: card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: .daysAgo(30)
        )
        let key = InsightKey.answer(
            "Which program are you studying?", variant: Intelligence.modelVariant, revision: AnswerRevision.of(fields)
        )
        let state = AppState(values: Alex.allValues, cardLink: link)
            .recording([CachedInsight(key: key, answer: "use:Major")], siteKinds: [:])
        let store = MemoryStore(state)
        let router = MessageRouter(store: store, gateway: FakeGateway(card: card), now: { .testNow })
        let ask = { (text: String) in
            router.route(["type": "customSuggestions", "host": "jobs.example.com", "fields": [["text": text]]])
        }
        #expect(ask("Which program are you studying?")
            == .customSuggestions(CustomSuggestionsResponse(fields: [.init(values: [], guesses: ["EECS"])])))
        #expect(ask("Favourite snack") == .customSuggestions(CustomSuggestionsResponse(fields: [.init(values: [])])))
        _ = ask("Favourite snack")
        #expect(try store.readEvents().questions == [
            FormQuestion(host: "example.com", text: "Favourite snack", date: .testNow)
        ])
    }
}
