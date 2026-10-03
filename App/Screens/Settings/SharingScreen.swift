import ContactsUI
import PrefillKit
import SwiftUI

// What people get when the person shares their card, and the links and custom fields still
// on it. Safari reads emails, phones and addresses from the card itself, so those stay;
// links and custom fields move to Prefill's own contact, but only when the person says so.
struct SharingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var skipped: Set<String> = []
    @State private var isConfirming = false

    var body: some View {
        Form {
            Section {
                ShareFact(
                    title: "NameDrop", systemImage: "iphone.radiowaves.left.and.right",
                    text: "Sends your name, your Contact Poster and the one phone number or email you pick."
                )
                ShareFact(
                    title: "Share Contact", systemImage: "square.and.arrow.up",
                    text: """
                        Sends everything on your card. Tap Filter Fields at the top of the share sheet \
                        and turn off what you want to keep to yourself.
                        """
                )
            } header: {
                Text("What people get").textRole(.groupHeader)
            }
            onCardSection
            if model.access == .limited {
                macSection
            }
        }
        .navigationTitle("Sharing your card")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var onCardSection: some View {
        if model.extrasOnCard.isEmpty {
            Section {
                Label("Your links and custom fields are off your card", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("card-is-clean")
            } footer: {
                Text("Prefill keeps them on its own contact, \(prefillName), so sharing your card leaves them out.")
                    .textRole(.footnote)
            }
        } else {
            Section {
                ForEach(model.extrasOnCard) { extra in
                    Toggle(isOn: chosen(extra)) {
                        VStack(alignment: .leading) {
                            Text(extra.title).textRole(.body)
                            Text(extra.value).textRole(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("extra-\(extra.id)")
                }
                Button("Move \(chosenExtras.count) off your card") { isConfirming = true }
                    .disabled(chosenExtras.isEmpty)
                    .accessibilityIdentifier("move-off-card")
                    .confirmationDialog(
                        "Move \(chosenExtras.count) off your card?", isPresented: $isConfirming,
                        titleVisibility: .visible
                    ) {
                        Button("Move off your card") {
                            Task { await model.moveOffCard(chosenExtras) }
                        }
                    } message: {
                        Text(confirmMessage)
                    }
            } header: {
                Text("Still on your card").textRole(.groupHeader)
            } footer: {
                Text("""
                    Share Contact sends these. Prefill copies the ones you turn on to its own contact, \
                    \(prefillName), then takes them off your card. Prefill still fills them in.
                    """)
                .textRole(.footnote)
            }
        }
    }

    private var macSection: some View {
        Section {
            ContactAccessButton(queryString: PrefillContact.searchName) { _ in
                Task { await model.refreshCard() }
            }
        } header: {
            Text("Using Prefill on a Mac too?").textRole(.groupHeader)
        } footer: {
            Text("""
                If your Mac already made the \(PrefillContact.searchName) contact, tap it here so this \
                iPhone uses the same links and custom fields.
                """)
            .textRole(.footnote)
        }
    }

    private var prefillName: String {
        model.card.map(PrefillContact.name(for:)) ?? PrefillContact.searchName
    }

    private var chosenExtras: [CardExtra] {
        model.extrasOnCard.filter { !skipped.contains($0.id) }
    }

    private var confirmMessage: String {
        let list = chosenExtras.map { "\($0.title): \($0.value)" }.joined(separator: "\n")
        return String(localized: "These come off your card and stay on \(prefillName):\n\(list)")
    }

    private func chosen(_ extra: CardExtra) -> Binding<Bool> {
        Binding { !skipped.contains(extra.id) } set: { isOn in
            skipped = isOn ? skipped.subtracting([extra.id]) : skipped.union([extra.id])
        }
    }
}

private struct ShareFact: View {
    let title: LocalizedStringKey
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(title).textRole(.body)
                Text(text).textRole(.footnote).foregroundStyle(Palette.textSecondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

#Preview {
    NavigationStack {
        SharingScreen()
    }
    .previewModel()
}
