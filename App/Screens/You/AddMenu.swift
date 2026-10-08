import PrefillKit
import SwiftUI

// What the Add menu can add, each with the sheet that adds it.
enum AddChoice: Identifiable, Hashable {
    case value(ContactKind)
    case answer
    case draft
    case studentAnswers

    var id: String {
        switch self {
        case .value(let kind): kind.rawValue
        case .answer: "answer"
        case .draft: "draft"
        case .studentAnswers: "student"
        }
    }

    @ViewBuilder func sheet(missingStudentAnswers: [JobQuestion]) -> some View {
        switch self {
        case .value(let kind): AddValueSheet(kind: kind)
        case .answer: CustomFieldSheet(original: nil)
        case .draft: CustomFieldSheet(original: nil, isDraft: true)
        case .studentAnswers: StudentAnswersSheet(missing: missingStudentAnswers) {}
        }
    }
}

// The one Add button: a menu of every kind of value, and the student starter set while
// any of its questions has no answer yet.
struct AddMenu: View {
    @Environment(AppModel.self) private var model
    let choose: (AddChoice) -> Void

    var body: some View {
        Menu {
            ForEach(ContactKind.allCases) { kind in
                Button(kind.menuTitle, systemImage: kind.symbol) { choose(.value(kind)) }
                    .accessibilityIdentifier("add-\(kind.rawValue)")
            }
            Button("Answer", systemImage: "text.bubble") { choose(.answer) }
                .accessibilityIdentifier("add-custom-field")
            Button("Draft answer…", systemImage: "doc.text") { choose(.draft) }
                .accessibilityIdentifier("add-draft")
            if !StudentStarter.missing(from: model.customFields).isEmpty {
                Divider()
                Button("Common student answers…", systemImage: "graduationcap") { choose(.studentAnswers) }
                    .accessibilityIdentifier("add-student-answers")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .accessibilityIdentifier("add-menu")
    }
}

private extension ContactKind {
    var menuTitle: LocalizedStringKey {
        switch self {
        case .email: "Email"
        case .phone: "Phone"
        case .address: "Address"
        case .link: "Link"
        }
    }
}
