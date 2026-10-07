import PrefillKit
import SwiftUI

// A label of the person's own, from the label menu's "Custom label…". Contacts' labels are in
// the menu itself.
struct RelabelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let value: ContactValue
    @State private var custom = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("For example, Side project", text: $custom)
                    .submitLabel(.done)
                    .onSubmit(applyCustom)
                    .focused($isFocused)
                    .accessibilityLabel("Label")
            }
            .navigationTitle("Custom label")
            .navigationSubtitle(value.display)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use label", action: applyCustom)
                        .disabled(trimmedCustom.isEmpty)
                }
            }
            .onAppear {
                if !LabelChoices.isSystem(value.label, kind: value.kind) { custom = value.label ?? "" }
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.canvas)
    }

    private var trimmedCustom: String {
        custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyCustom() {
        guard !trimmedCustom.isEmpty else { return }
        dismiss()
        Task { await model.relabel(value, to: trimmedCustom) }
    }
}

struct AddValueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: ContactKind

    @State private var draft = ValueDraft()
    @State private var label: String?
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fields
                } footer: {
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.destructive)
                    }
                }
                Section {
                    Picker("Label", selection: $label) {
                        Text(kind == .link ? "Automatic" : "No label").tag(String?.none)
                        ForEach(LabelChoices.system(for: kind), id: \.self) { choice in
                            Text(LabelChoices.caption(choice, kind: kind)).tag(Optional(choice))
                        }
                    }
                }
            }
            .navigationTitle(kind.addTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await submit() } }
                        .accessibilityIdentifier("add-to-card")
                }
            }
            .onAppear { isFocused = true }
        }
    }

    @ViewBuilder private var fields: some View {
        switch kind {
        case .email:
            TextField("name@example.com", text: $draft.email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .accessibilityLabel("Email")
                .spokenProblem(error, typed: draft.email)
        case .phone:
            TextField("Phone number", text: $draft.phone)
                .keyboardType(.phonePad)
                .focused($isFocused)
                .spokenProblem(error, typed: draft.phone)
        case .address:
            AddressField(title: "Street", prompt: "Required", text: $draft.street, problem: error)
                .focused($isFocused)
            AddressField(title: "City", text: $draft.city)
            AddressField(title: "State", text: $draft.state)
            AddressField(title: "Postal code", text: $draft.postalCode)
            AddressField(title: "Country", text: $draft.country)
        case .link:
            TextField("github.com/yourname", text: $draft.link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .accessibilityLabel("Link")
                .accessibilityIdentifier("link-field")
                .spokenProblem(error, typed: draft.link)
        }
    }

    private func submit() async {
        switch draft.payload(kind) {
        case .failure(let problem):
            report(problem.message)
        case .success(let payload):
            switch await model.add(payload, label: label ?? payload.automaticLabel) {
            case .added: dismiss()
            case .alreadyOnCard: report(String(localized: "That’s already on your card."))
            case .failed(let failure): report(failure.appMessage)
            }
        }
    }

    // The footer shows the problem; VoiceOver hears it now and again on the field, which
    // takes focus back.
    private func report(_ message: String) {
        error = message
        AccessibilityNotification.Announcement(message).post()
        isFocused = true
    }
}

// No text content type on purpose: iOS would offer the card's own values here, and those are
// the one answer this form can't take. The name stays beside the field once it's filled in,
// or above it at accessibility sizes, where there's no room beside it.
private struct AddressField: View {
    let title: LocalizedStringKey
    var prompt: LocalizedStringKey = "Optional"
    @Binding var text: String
    var problem: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var labelWidth = Size.fieldLabel

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxSmall))
            : AnyLayout(HStackLayout(spacing: Spacing.small))
    }

    var body: some View {
        layout {
            Text(title)
                .textRole(.body)
                .frame(width: typeSize.isAccessibilitySize ? nil : labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            TextField(title, text: $text, prompt: Text(prompt))
                .textInputAutocapitalization(.words)
                .spokenProblem(problem, typed: text)
        }
    }
}

private extension View {
    // Adds a validation problem to what VoiceOver reads as the field's value, after the text.
    func spokenProblem(_ problem: String?, typed: String) -> some View {
        let spoken = [typed, problem ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        return accessibilityValue(Text(verbatim: spoken))
    }
}

private extension ContactPayload {
    // A link with no label picked is labeled by its site, the way Prefill saves one from a form.
    var automaticLabel: String? {
        guard case .link(let url) = self else { return nil }
        return LinkType.of(url).label
    }
}

#Preview("Relabel") {
    RelabelSheet(value: PreviewData.emails[2])
        .previewModel()
}

#Preview("Add") {
    AddValueSheet(kind: .address)
        .previewModel()
}
