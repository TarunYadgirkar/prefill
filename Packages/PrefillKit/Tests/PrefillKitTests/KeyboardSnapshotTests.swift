import Foundation
import Testing
@testable import PrefillKit

private let github = CardEntry(label: "GitHub", payload: .link("https://github.com/alexrivera"))
private let site = CardEntry(label: "_$!<HomePage>!$_", payload: .link("https://alexrivera.dev"))
private let school = CustomField(label: "School", value: "UC Berkeley", matchWords: [])
private let card = Alex.card.replacing(.link, with: [github, site]).replacingCustomFields(with: [school])

private func snapshot(events: ExtensionEvents = ExtensionEvents()) -> KeyboardSnapshot {
    let memory = Memory.read(card: card, placement: CardPlacement(onCard: []), state: AppState(), events: events)
    return KeyboardSnapshot.make(memory: memory, now: .testNow)
}

struct KeyboardSnapshotTests {
    @Test func everyAnswerBecomesAValueWithACaption() {
        let values = snapshot().values
        let pairs = values.map { "\($0.label): \($0.text)" }
        #expect(pairs == [
            "Name: Alex Rivera", "First name: Alex", "Last name: Rivera",
            "Home email: alex.rivera@example.com", "Work email: alex@work.example.org",
            "Email: alex.school@example.edu",
            "Mobile: +1 (510) 555-0134", "Work phone: +1 (415) 555-0199",
            "Home address: 2400 Durant Ave, Berkeley, CA 94704",
            "Work address: 1 Market St Suite 300, San Francisco, CA 94105",
            "GitHub: https://github.com/alexrivera", "Website: https://alexrivera.dev",
            "School: UC Berkeley"
        ])
        #expect(values.first { $0.kind == .link }?.shownText == "github.com/alexrivera")
    }

    @Test func recentlyUsedValuesComeFirstWithinTheirKind() {
        let events = ExtensionEvents(
            usage: [
                UsageEvent(valueID: Alex.schoolEmail.id, host: "a.example.com", date: .daysAgo(5)),
                UsageEvent(valueID: Alex.workEmail.id, host: "b.example.com", date: .daysAgo(1))
            ]
        )
        let emails = snapshot(events: events).values.filter { $0.kind == .email }
        #expect(emails.map(\.text) == ["alex@work.example.org", "alex.school@example.edu", "alex.rivera@example.com"])
        #expect(emails.first?.lastUsed == .daysAgo(1))
    }

    @Test func theSnapshotIsCapped() {
        let fields = (0..<CustomField.maxCount).map { CustomField(label: "Q\($0)", value: "A\($0)", matchWords: []) }
        let links = (0..<70).map { CardEntry(label: nil, payload: .link("https://example.com/\($0)")) }
        let big = card.replacing(.link, with: links).replacingCustomFields(with: fields)
        let memory = Memory.read(card: big, placement: CardPlacement(onCard: []), state: AppState(), events: .init())
        #expect(KeyboardSnapshot.make(memory: memory).values.count == KeyboardSnapshot.maxValues)
    }
}

struct KeyboardShareTests {
    @Test func theAppGroupBackendKeepsTheSnapshotAndWhenTheKeyboardWasSeen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let share = KeyboardShare(store: AppGroupStore(directory: directory))
        #expect(try share.readSnapshot() == nil)
        try share.writeSnapshot(snapshot())
        try share.writeSeen(.testNow)
        #expect(try share.readSnapshot() == snapshot())
        #expect(try share.readSeen() == .testNow)
        try AppGroupStore(directory: directory).removeAll()
        #expect(try share.readSeen() == nil)
    }
}
