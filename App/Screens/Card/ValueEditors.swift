import PrefillKit
import SwiftUI

struct RelabelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let value: ContactValue
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(LabelChoices.system(for: value.kind), id: \.self) { label in
                        choice(LabelChoices.caption(label, kind: value.kind), label: label)
                    }
                    choice(String(localized: "No label"), label: nil)
                } header: {
                    Text(value.display.breakableAtPunctuation)
                        .textRole(.value)
                        .textCase(nil)
                }
                Section("Your own label") {
                    TextField("For example, Side project", text: $custom)
                        .submitLabel(.done)
                        .onSubmit(applyCustom)
                    Button("Use this label", action: applyCustom)
                        .disabled(trimmedCustom.isEmpty)
                }
            }
            .navigationTitle("Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .onAppear {
                if !LabelChoices.isSystem(value.label, kind: value.kind) { custom = value.label ?? "" }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedCustom: String {
        custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func choice(_ title: String, label: String?) -> some View {
        Button {
            apply(label)
        } label: {
            HStack {
                Text(title).textRole(.body)
                Spacer()
                if value.label == label {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(value.label == label ? .isSelected : [])
    }

    private func applyCustom() {
        guard !trimmedCustom.isEmpty else { return }
        apply(trimmedCustom)
    }

    private func apply(_ label: String?) {
        dismiss()
        Task { await model.relabel(value, to: label) }
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
                Section("Label") {
                    Picker("Label", selection: $label) {
                        Text("No label").tag(String?.none)
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
                    Button("Add to card") { Task { await submit() } }
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
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .accessibilityLabel("Email")
        case .phone:
            TextField("Phone number", text: $draft.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .focused($isFocused)
        case .address:
            TextField("Street", text: $draft.street).textContentType(.fullStreetAddress).focused($isFocused)
            TextField("City", text: $draft.city).textContentType(.addressCity)
            TextField("State", text: $draft.state).textContentType(.addressState)
            TextField("ZIP or postal code", text: $draft.postalCode).textContentType(.postalCode)
            TextField("Country", text: $draft.country).textContentType(.countryName)
        }
    }

    private func submit() async {
        switch draft.payload(kind) {
        case .failure(let problem):
            error = problem.message
        case .success(let payload):
            if await model.add(payload, label: label) {
                dismiss()
            } else {
                error = String(localized: "That's already on your card.")
            }
        }
    }
}

struct ValueDraft {
    struct Problem: Error {
        let message: String
    }

    private static let minPhoneDigits = 7

    var email = ""
    var phone = ""
    var street = ""
    var city = ""
    var state = ""
    var postalCode = ""
    var country = ""

    func payload(_ kind: ContactKind) -> Result<ContactPayload, Problem> {
        switch kind {
        case .email: emailPayload()
        case .phone: phonePayload()
        case .address: addressPayload()
        }
    }

    private func emailPayload() -> Result<ContactPayload, Problem> {
        let text = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasSuffix(".") else {
            return .failure(Problem(message: String(localized: "Enter an email address like name@example.com.")))
        }
        return .success(.email(text))
    }

    private func phonePayload() -> Result<ContactPayload, Problem> {
        let text = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.filter(\.isNumber).count >= Self.minPhoneDigits else {
            return .failure(Problem(message: String(localized: "Enter a phone number with at least 7 digits.")))
        }
        return .success(.phone(text))
    }

    private func addressPayload() -> Result<ContactPayload, Problem> {
        let trim = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trim(street).isEmpty else {
            return .failure(Problem(message: String(localized: "Enter the street part of the address.")))
        }
        return .success(.address(PostalAddress(
            street: trim(street), city: trim(city), state: trim(state),
            postalCode: trim(postalCode), country: trim(country)
        )))
    }
}

struct EmptyKind: View {
    let kind: ContactKind
    let add: () -> Void

    var body: some View {
        EmptyStateView(title: title, systemImage: kind.symbol, message: Text("""
            Add one here, or fill in a form in Safari and Prefill saves it to your card.
            """)) {
            PrefillButton(title: kind.addTitle, systemImage: "plus", action: add)
                .fixedSize()
        }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .email: "No emails on your card"
        case .phone: "No phone numbers on your card"
        case .address: "No addresses on your card"
        }
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
