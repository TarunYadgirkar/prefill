import PrefillKit
import SwiftUI

// Changes one email, phone number, address or link: its label and what it says. The card
// takes the change in one save, in the value's place, so nothing else on it moves.
struct ValueEditForm: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let value: ContactValue

    @State private var label: String?
    @State private var draft = ValueDraft()
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Picker("Label", selection: $label) {
                ForEach(labels, id: \.self) { choice in
                    Text(LabelChoices.caption(choice, kind: value.kind)).tag(choice)
                }
            }
            fields
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(Spacing.medium)
        .frame(width: Size.settingsWidth - Spacing.medium * 2)
        .onAppear {
            label = value.label
            draft = ValueDraft(value.payload)
        }
    }

    @ViewBuilder private var fields: some View {
        switch value.kind {
        case .email: TextField("Email", text: $draft.email, prompt: Text("name@example.com"))
        case .phone: TextField("Phone", text: $draft.phone, prompt: Text("+1 (510) 555-0134"))
        case .link: TextField("Link", text: $draft.link, prompt: Text("github.com/yourname"))
        case .address:
            TextField("Street", text: $draft.street)
            TextField("City", text: $draft.city)
            TextField("State", text: $draft.state)
            TextField("Postal code", text: $draft.postalCode)
            TextField("Country", text: $draft.country)
        }
    }

    // The kind's usual labels, plus the value's own: one the person made up, or none.
    private var labels: [String?] {
        let system: [String?] = LabelChoices.system(for: value.kind)
        return system.contains(value.label) ? system : [value.label] + system
    }

    private func submit() async {
        isSaving = true
        defer { isSaving = false }
        if let problem = await model.editValue(value, label: label, draft: draft) {
            error = problem
        } else {
            dismiss()
        }
    }
}
