import PrefillKit
import SwiftUI

// What sort of answer this is, what it applies to and where it came from.
struct AnswerFactsSection: View {
    let answer: Answer

    var body: some View {
        Section {
            LabeledContent("Kind", value: answer.kind.title)
                .accessibilityIdentifier("answer-kind")
            if let scope = answer.scope {
                LabeledContent("Applies to", value: scope.name)
                    .accessibilityIdentifier("answer-scope")
            }
            LabeledContent("Source", value: answer.origin.title)
                .accessibilityIdentifier("answer-source")
        } footer: {
            Text(answer.kind.footer).textRole(.footnote)
        }
    }
}

// Where Prefill saved or changed the answer, newest first, as this iPhone saw it.
struct ChangesSection: View {
    let changes: [AnswerChange]

    var body: some View {
        if !changes.isEmpty {
            Section {
                ForEach(changes, id: \.self) { change in
                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(change.what.title(site: change.site.breakableAtPunctuation)).textRole(.body)
                        Text(change.date.formatted(.relative(presentation: .named))).textRole(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("History").textRole(.groupHeader)
            } footer: {
                Text("From this iPhone only.").textRole(.footnote)
            }
        }
    }
}

extension Answer.Kind {
    var title: String {
        switch self {
        case .fact: String(localized: "Fact")
        case .contextualFact: String(localized: "Fact for one place or term")
        case .preference: String(localized: "Rule")
        case .draft: String(localized: "Draft")
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .fact: "Fill form uses it wherever a question asks for it."
        case .contextualFact: "Fill form uses it only where the question names the same place or term."
        case .preference: "Prefill follows it on every form."
        case .draft: "Offered in Prefill’s list for you to pick and edit. Fill form never uses it."
        }
    }
}

private extension Answer.Origin {
    var title: String {
        switch self {
        case .card: String(localized: "Your contact card")
        case .captured(let host?): String(localized: "Typed on \(host)")
        case .captured(nil): String(localized: "Typed on a form")
        case .learned(let host): String(localized: "Learned from \(host)")
        case .typedInApp: String(localized: "Added in Prefill")
        case .resume: String(localized: "Your resume")
        }
    }
}

private extension AnswerChange.What {
    func title(site: String) -> LocalizedStringKey {
        switch self {
        case .saved: "Saved from \(site)"
        case .replaced(let previous): "Changed on \(site) from “\(previous)”"
        }
    }
}
