import Contacts
import Foundation
import Testing
@testable import PrefillKit

private let letter = "Dear hiring team,\nI build tools people use every day."
private let draft = (try? CustomField.make(label: "Cover letter", value: letter, alsoMatches: "", isDraft: true).get())!
private let school = (try? CustomField.make(label: "School", value: "UC Berkeley", alsoMatches: "").get())!

// What builds from before drafts did with a related name: Prefill's only when the part after
// the label is exactly "Prefill", and every other related name kept as it was on a rewrite.
private func legacyDecode(_ label: String?) -> Bool {
    guard let parts = label?.components(separatedBy: " · "), (2...3).contains(parts.count) else { return false }
    return parts[1] == "Prefill"
}

struct DraftTests {
    @Test func aDraftKeepsLineBreaksAndLongTextOnlyWhenItIsADraft() {
        let long = String(repeating: "a", count: CustomField.maxDraftValue)
        let make = { (label: String, value: String, isDraft: Bool) in
            try? CustomField.make(label: label, value: value, alsoMatches: "", isDraft: isDraft).get()
        }
        #expect(make("Why us", long, true) != nil)
        #expect(make("Why us", long + "a", true) == nil)
        #expect(make("Cover letter", letter, false) == nil)
        #expect(make("Cover\nletter", "Hi", true) == nil)
    }

    @Test func aDraftRoundTripsOnTheCardAndOlderBuildsLeaveItAlone() {
        #expect(CustomFieldLabel.encode(draft) == "Cover letter · Prefill draft")
        #expect(CustomFieldLabel.decode(label: CustomFieldLabel.encode(draft), value: letter) == draft)
        #expect(!legacyDecode(CustomFieldLabel.encode(draft)))
        #expect(legacyDecode(CustomFieldLabel.encode(school)))

        let contact = CNMutableContact()
        CNCardMapping.apply(Alex.card.replacingCustomFields(with: [school, draft]), to: contact)
        let relations = contact.contactRelations
        #expect(relations.map(\.value.name) == ["UC Berkeley", letter])
        // An older build rewrites only the related names it reads as Prefill's.
        let kept = relations.filter { !legacyDecode($0.label) }
        #expect(kept.map(\.value.name) == [letter])
        #expect(CNCardMapping.record(from: contact, identifier: "alex").customFields == [school, draft])
    }

    @Test func storedRecordsFromBeforeDraftsStillRead() throws {
        let old = Data(#"{"label":"School","value":"UC Berkeley","matchWords":[]}"#.utf8)
        #expect(try JSONDecoder().decode(CustomField.self, from: old) == school)
        let encoded = try #require(String(data: try JSONEncoder().encode(school), encoding: .utf8))
        #expect(!encoded.contains("isDraft"))
        #expect(try JSONDecoder().decode(CustomField.self, from: try JSONEncoder().encode(draft)) == draft)
    }

    // Only the field the person is in gets a draft, as an offer: never a value Fill form uses,
    // and never remembered as the question's answer.
    @Test func aDraftIsOfferedToTheFocusedFieldOnlyAndNeverFilled() throws {
        let card = Alex.card.replacingCustomFields(with: [school, draft])
        let link = CardLink(
            contactIdentifier: card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        let router = MessageRouter(store: store, gateway: FakeGateway(card: card), now: { .testNow })
        let ask = { (texts: [String], focused: Bool) in
            router.route([
                "type": "customSuggestions", "host": "jobs.lever.co",
                "fields": texts.map { focused ? ["text": $0, "focused": true] : ["text": $0] }
            ])
        }
        let offered = SuggestedValue(value: letter, why: .draft, label: "Cover letter")
        #expect(ask(["Cover letter"], true)
            == .customSuggestions(CustomSuggestionsResponse(fields: [.init(values: [], drafts: [offered])])))
        // A page-load request, even about the one field, never gets a draft.
        #expect(ask(["Cover letter"], false)
            == .customSuggestions(CustomSuggestionsResponse(fields: [.init(values: [])])))
        #expect(ask(["Cover letter", "School"], true) == .customSuggestions(CustomSuggestionsResponse(fields: [
            .init(values: []), .init(values: [SuggestedValue(value: "UC Berkeley", label: "School")])
        ])))
        _ = router.route([
            "type": "picked", "host": "jobs.lever.co", "kind": "custom", "value": "Hi", "question": "Cover letter"
        ])
        #expect(try store.readEvents().answerPicks.isEmpty)
    }

    // Drafts have their own limit, so they never take the room a learned answer needs.
    @Test func draftsAreCountedApartFromAnswers() {
        let answers = (1...CustomField.maxCount).map { CustomField(label: "Q\($0)", value: "A", matchWords: []) }
        let drafts = (1...CustomField.maxDrafts).map {
            CustomField(label: "D\($0)", value: "Text", matchWords: [], isDraft: true)
        }
        let full = answers + drafts
        let extraDraft = CustomField(label: "D9", value: "Text", matchWords: [], isDraft: true)
        #expect((try? full.saving(extraDraft, replacing: nil).get()) == nil)
        #expect((try? (answers.dropLast() + drafts).saving(school, replacing: nil).get())?.count == full.count)
        #expect(full.answerCount == CustomField.maxCount)
    }

    @Test func memoryNamesEachAnswersKind() {
        let scoped = CustomField(label: "Work authorization (US)", value: "Yes", matchWords: [])
        let card = Alex.card.replacingCustomFields(with: [school, scoped, draft])
        let memory = Memory.read(
            card: card, placement: CardPlacement(onCard: [], onPrefill: []), state: AppState(),
            events: ExtensionEvents()
        )
        let custom = memory.answers.filter { if case .custom = $0.question { true } else { false } }
        #expect(custom.map(\.kind) == [.fact, .contextualFact, .draft])
        #expect(custom[1].scope == AnswerScope(kind: .country, name: "US"))
        #expect(memory.answers.filter { if case .kind = $0.question { true } else { false } }.allSatisfy {
            $0.kind == .fact
        })
        #expect(memory.preferences.map(\.kind) == [.preference])
    }

    @Test func historyShowsWhereAnAnswerWasSavedAndChanged() {
        let auth = CustomField(label: "Work authorization", value: "Yes", matchWords: [])
        let events = ExtensionEvents(answers: [
            LearnedAnswer(host: "lever.co", label: "Work authorization", value: "No", date: .daysAgo(3)),
            LearnedAnswer(
                host: "greenhouse.io", label: "Work authorization", value: "Yes", date: .daysAgo(1), previous: "No"
            )
        ])
        let memory = Memory.read(
            card: Alex.card.replacingCustomFields(with: [auth]), placement: CardPlacement(onCard: [], onPrefill: []),
            state: AppState(), events: events
        )
        let answer = try? #require(memory.answers.first { $0.question == .custom(label: "Work authorization") })
        #expect(answer.map(memory.changes(of:))?.map(\.what) == [.replaced(previous: "No"), .saved])
    }
}
