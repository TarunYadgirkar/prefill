import Foundation
import Testing
@testable import PrefillKit

private let github = CardEntry(label: "GitHub", payload: .link("https://github.com/alexrivera"))
private let school = CustomField(label: "School", value: "UC Berkeley", matchWords: ["university"])
private let gpa = CustomField(label: "GPA", value: "3.8", matchWords: [])
private let card = Alex.card.replacing(.link, with: [github]).replacingCustomFields(with: [school, gpa])

private func extras(_ kinds: [ContactKind]) -> [CardExtra] {
    kinds.flatMap { card.entries($0).map(CardExtra.entry) }
}

private let fullPlacement = CardPlacement(
    onCard: extras([.email, .phone, .address]),
    onPrefill: extras([.link]) + card.customFields.map(CardExtra.customField)
)
private let minimalPlacement = CardPlacement(
    onCard: extras([.phone]),
    onPrefill: extras([.email, .address, .link]) + card.customFields.map(CardExtra.customField), isMinimal: true
)

struct MemoryTests {
    private func memory(
        placement: CardPlacement = fullPlacement, state: AppState = AppState(),
        events: ExtensionEvents = ExtensionEvents()
    ) throws -> Memory {
        let gateway = FakeGateway(card: card)
        gateway.state.withLock { $0.placement = placement }
        return try Memory.read(gateway: gateway, identifier: card.identifier, state: state, events: events)
    }

    @Test func minimalAndFullCardsGiveTheSameAnswersInDifferentPlaces() throws {
        let full = try memory()
        let minimal = try memory(placement: minimalPlacement)
        let strip = { (memory: Memory) in memory.answers.map { [$0.id.uuidString, $0.text, $0.label ?? ""] } }
        #expect(strip(full) == strip(minimal))
        #expect(full.answers.count == 10)
        #expect(full.name == Memory.Name(given: "Alex", family: "Rivera"))

        let email = Alex.homeEmail.id
        #expect(full.answers.first { $0.id == email }?.place == .meCard)
        #expect(minimal.answers.first { $0.id == email }?.place == .prefillContact)
        #expect(minimal.answers(for: .kind(.phone)).allSatisfy { $0.place == .meCard })
        #expect(full.answers(for: .kind(.link)).map(\.place) == [.prefillContact])
    }

    @Test func aCardWithoutAPrefillContactKeepsEverythingOnIt() throws {
        let memory = try memory(placement: CardPlacement(onCard: []))
        #expect(memory.answers.allSatisfy { $0.place == .meCard })
    }

    @Test func customFieldsAreAnsweredByTheirLabel() throws {
        let memory = try memory()
        let answers = memory.answers(for: .custom(label: "School"))
        #expect(answers.map(\.text) == ["UC Berkeley"])
        #expect(answers.first?.label == nil)
        let edited = card.replacingCustomFields(with: [CustomField(label: "school", value: "MIT", matchWords: [])])
        let reread = Memory.read(card: edited, placement: fullPlacement, state: AppState(), events: ExtensionEvents())
        #expect(reread.answers.last?.id == answers.first?.id)
        #expect(reread.answers.last?.id != Answer.customID(gpa))
    }

    @Test func originsComeFromStateCapturesAndLearnedAnswers() throws {
        let typed = Alex.value(.email("alex.rivera@example.com"), label: Alex.homeLabel, source: .typedInApp)
        let captured = Alex.value(.phone("+1 (415) 555-0199"), label: Alex.workLabel, source: .captured)
        let events = ExtensionEvents(
            captures: [
                Capture(host: "jobs.example.io", value: captured, date: .daysAgo(9), verdict: .saved),
                Capture(host: "later.example.io", value: captured, date: .daysAgo(2), verdict: .saved),
                Capture(host: "shop.example.com", value: Alex.schoolEmail, date: .daysAgo(3), verdict: .needsReview)
            ],
            answers: [
                LearnedAnswer(host: "boards.greenhouse.io", label: "School", value: "UC Berkeley", date: .daysAgo(5))
            ]
        )
        let state = AppState(values: [typed, captured, Alex.mobile])
        let memory = try memory(state: state, events: events)
        let origin = { (id: UUID) in memory.answers.first { $0.id == id }?.origin }
        #expect(origin(typed.id) == .typedInApp)
        #expect(origin(captured.id) == .captured(host: "jobs.example.io"))
        #expect(origin(Alex.mobile.id) == .card)
        #expect(origin(Alex.schoolEmail.id) == .captured(host: "shop.example.com"))
        #expect(origin(Alex.workEmail.id) == .card)
        #expect(origin(Answer.customID(school)) == .learned(host: "boards.greenhouse.io"))
        #expect(origin(Answer.customID(gpa)) == .typedInApp)
        #expect(memory.answers.first { $0.id == Answer.customID(school) }?.createdAt == .daysAgo(5))
    }
}

struct MemoryUsesTests {
    @Test func usesAreNewestFirstOncePerSite() throws {
        let email = Alex.workEmail.id
        let events = ExtensionEvents(
            usage: [
                UsageEvent(valueID: email, host: "example.io", date: .daysAgo(10)),
                UsageEvent(valueID: email, host: "lever.co", date: .daysAgo(4)),
                UsageEvent(valueID: email, host: "example.io", date: .daysAgo(1)),
                UsageEvent(valueID: Alex.homeEmail.id, host: "other.com", date: .daysAgo(1))
            ],
            pins: [
                PinEvent(host: "shop.example.com", kind: .email, valueID: email, date: .daysAgo(2)),
                PinEvent(host: "gone.com", kind: .email, valueID: nil, date: .daysAgo(2))
            ],
            answers: [
                LearnedAnswer(host: "boards.greenhouse.io", label: "School", value: "UC Berkeley", date: .daysAgo(6)),
                LearnedAnswer(host: "jobs.lever.co", label: "School", value: "Stanford", date: .daysAgo(3))
            ]
        )
        let memory = Memory.read(card: card, placement: fullPlacement, state: AppState(), events: events)
        let sites = { (id: UUID) in memory.answers.first { $0.id == id }.map { memory.uses(of: $0).map(\.site) } }
        #expect(sites(email) == ["example.io", "example.com", "lever.co"])
        let answer = try #require(memory.answers.first { $0.id == email })
        #expect(memory.uses(of: answer).first?.date == .daysAgo(1))
        #expect(sites(Answer.customID(school)) == ["greenhouse.io"])
        #expect(sites(Answer.customID(gpa)) == [])
    }
}
