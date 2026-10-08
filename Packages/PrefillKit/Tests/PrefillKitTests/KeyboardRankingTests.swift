import Foundation
import Testing
@testable import PrefillKit

private let name = KeyboardValue(kind: .name, label: KeyboardValue.fullNameLabel, text: "Alex Rivera")
private let given = KeyboardValue(kind: .name, label: KeyboardValue.givenNameLabel, text: "Alex")
private let home = KeyboardValue(kind: .email, label: "Home email", text: "alex.rivera@example.com")
private let work = KeyboardValue(kind: .email, label: "Work email", text: "alex@work.example.org")
private let mobile = KeyboardValue(kind: .phone, label: "Mobile", text: "+1 (510) 555-0134")
private let address = KeyboardValue(kind: .address, label: "Home address", text: "2400 Durant Ave, Berkeley, CA")
private let site = KeyboardValue(kind: .link, label: "Website", text: "https://alexrivera.dev")
private let github = KeyboardValue(kind: .link, label: "GitHub", text: "https://github.com/alexrivera")
private let linkedin = KeyboardValue(kind: .link, label: "LinkedIn", text: "https://www.linkedin.com/in/alexr")
private let school = KeyboardValue(kind: .custom, label: "School", text: "UC Berkeley")
private let all = [name, given, home, work, mobile, address, site, github, linkedin, school]

private func ranked(
    _ values: [KeyboardValue] = all, before: String = "", hint: KeyboardFieldHint? = nil, recent: [KeyboardValue] = []
) -> [String] {
    let context = KeyboardContext(before: before, hint: hint, recentPicks: recent.map(\.id))
    return KeyboardSnapshot(values: values, writtenAt: .testNow).ranked(for: context).map(\.label)
}

struct KeyboardRankingTests {
    @Test func withNoSignalTheFixedOrderLeads() {
        #expect(ranked() == [
            "Name", "Home email", "Mobile", "LinkedIn", "GitHub", "Website", "School",
            "First name", "Work email", "Home address"
        ])
    }

    @Test func typedTextNarrowsByValueAndCaption() {
        #expect(ranked(before: "git").first == "GitHub")
        #expect(ranked(before: "My profile: github.com/").first == "GitHub")
        #expect(ranked(before: "linkedin").first == "LinkedIn")
        #expect(ranked(before: "alex@").prefix(1) == ["Work email"])
        #expect(ranked(before: "me@").prefix(2) == ["Home email", "Work email"])
        #expect(ranked(before: "(510) 55").first == "Mobile")
        #expect(ranked(before: "555").first == "Mobile")
    }

    @Test func aValueAlreadyInTheFieldIsNotOfferedAgain() {
        let shown = ranked(before: "alex@work.example.org")
        #expect(!shown.contains("Work email"))
        #expect(!ranked(before: "github.com/alexrivera").contains("GitHub"))
    }

    @Test func theFieldsTraitsComeAfterTypedText() {
        #expect(ranked(hint: .email).prefix(2) == ["Home email", "Work email"])
        #expect(ranked(before: "git", hint: .email).first == "GitHub")
    }

    @Test func recentPicksBeatLastUseAndTheFixedOrder() {
        let used = KeyboardValue(kind: .custom, label: "Pronouns", text: "they/them", lastUsed: .daysAgo(1))
        let values = all + [used]
        #expect(ranked(values).first == "Pronouns")
        #expect(ranked(values, recent: [school, github]).prefix(3) == ["School", "GitHub", "Pronouns"])
        #expect(ranked(values, hint: .link, recent: [school, site]).prefix(2) == ["Website", "LinkedIn"])
    }

    @Test func tiesKeepTheSnapshotOrder() {
        let answers = (0..<3).map { KeyboardValue(kind: .custom, label: "Q\($0)", text: "A\($0)") }
        #expect(ranked(answers) == ["Q0", "Q1", "Q2"])
        #expect(ranked(answers.reversed()) == ["Q2", "Q1", "Q0"])
    }

    @Test func aTapReplacesTheWordThatLedToIt() {
        let context = KeyboardContext(before: "Find me at github.com/")
        #expect(context.replacedLength(for: github) == "github.com/".count)
        #expect(context.replacedLength(for: school) == 0)
        #expect(KeyboardContext(before: "(510) 55").replacedLength(for: mobile) == "(510) 55".count)
        #expect(KeyboardContext().replacedLength(for: name) == 0)
    }

    @Test func recentPicksStayUniqueAndCapped() {
        let picks = (0..<40).reduce(KeyboardRecents()) { $0.picking("v\($1)") }.picking("v5")
        #expect(picks.ids.count == KeyboardRecents.maxCount)
        #expect(picks.ids.prefix(2) == ["v5", "v39"])
        #expect(picks.ids.filter { $0 == "v5" }.count == 1)
    }
}
