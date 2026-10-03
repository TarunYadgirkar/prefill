import PrefillKit
import SwiftUI

// Answers forms ask for that aren't on the card, like a school or a major. They live on the
// card as related names, so the iPhone app shows the same list.
struct CustomFieldsSection: View {
    @Environment(MacModel.self) private var model
    @State private var editing: CustomField?
    @State private var isAdding = false

    var body: some View {
        Section {
            ForEach(model.customFields) { field in
                CustomFieldRow(field: field) {
                    editing = field
                } remove: {
                    Task { await model.removeCustomField(field) }
                }
            }
            Button("Add field…") { isAdding = true }
                .disabled(model.card == nil)
        } header: {
            Text("Custom fields")
        } footer: {
            Text("""
                Chrome and Arc offer a field when a form asks for its label or one of its other words. \
                The same fields show in Prefill on your iPhone.
                """)
            .foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { field in
            CustomFieldForm(original: field)
        }
        .sheet(isPresented: $isAdding) {
            CustomFieldForm(original: nil)
        }
    }
}

private struct CustomFieldRow: View {
    let field: CustomField
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(field.label).foregroundStyle(.secondary)
                Text(field.value)
                if !field.matchWords.isEmpty {
                    Text("Also matches \(field.alsoMatches)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Edit…", action: edit)
            Button("Remove", role: .destructive, action: remove)
        }
    }
}

private struct CustomFieldForm: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let original: CustomField?

    @State private var label = ""
    @State private var value = ""
    @State private var alsoMatches = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Label", text: $label, prompt: Text("School"))
            TextField("Answer", text: $value, prompt: Text("UC Berkeley"))
            TextField("Also matches", text: $alsoMatches, prompt: Text("university, college"))
            Text("Other words a form might use for this field, separated by commas. Optional.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: Size.settingsWidth - Spacing.medium * 2)
        .onAppear {
            label = original?.label ?? ""
            value = original?.value ?? ""
            alsoMatches = original?.alsoMatches ?? ""
        }
    }

    private func submit() async {
        switch CustomField.make(label: label, value: value, alsoMatches: alsoMatches) {
        case .failure(let problem):
            error = problem.message
        case .success(let field):
            if let problem = await model.saveCustomField(field, replacing: original) {
                error = problem
            } else {
                dismiss()
            }
        }
    }
}
