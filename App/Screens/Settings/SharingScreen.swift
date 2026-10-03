import ContactsUI
import PrefillKit
import SwiftUI

// What people get when the person shares their card, and what is still on it. The screen
// recommends a minimal card: only the name and the phone number the person keeps stay on
// it, and everything else moves to Prefill's own contact, but only once they confirm.
struct SharingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var choices: [String: Bool] = [:]
    @State private var isConfirming = false

    var body: some View {
        Form {
            Section {
                ShareFact(
                    title: "NameDrop", systemImage: "iphone.radiowaves.left.and.right",
                    text: """
                        Sends your name, your Contact Poster and one phone number or email you pick. \
                        Pick your phone number.
                        """
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
            if !heldPhones.isEmpty {
                heldPhonesSection
            }
            if model.access == .limited {
                macSection
            }
        }
        .navigationTitle("Sharing your card")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var onCardSection: some View {
        if model.placement.suggestedMoves.isEmpty {
            Section {
                Label("Your card holds only your name and phone number", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("card-is-clean")
            } footer: {
                Text("""
                    Prefill keeps everything else on its own contact, \(prefillName), and offers it in Safari \
                    as its own suggestions.
                    """)
                .textRole(.footnote)
            }
        } else {
            Section {
                ForEach(model.placement.onCard) { extra in
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
                Text("Keep only your name and phone").textRole(.groupHeader)
            } footer: {
                Text(minimalFooter).textRole(.footnote)
            }
        }
    }

    private var heldPhonesSection: some View {
        Section {
            ForEach(heldPhones) { extra in
                LabeledContent {
                    Button("Put on your card") {
                        Task { await model.putOnCard(extra) }
                    }
                    .accessibilityIdentifier("promote-\(extra.id)")
                } label: {
                    Text(extra.title).textRole(.body)
                    Text(extra.value).textRole(.footnote)
                }
            }
        } header: {
            Text("Phone numbers on Prefill’s contact").textRole(.groupHeader)
        } footer: {
            Text("Safari’s bar offers the phone numbers on your card. Prefill doesn’t replace them there.")
                .textRole(.footnote)
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
                iPhone uses the same values.
                """)
            .textRole(.footnote)
        }
    }

    private var minimalFooter: String {
        String(localized: """
            Prefill copies the ones you turn on to its own contact, \(prefillName), then takes them off your \
            card, so sharing your card sends only what stays. In Safari, emails and addresses then show as \
            Prefill’s suggestions, at most 3 at a time, and AutoFill Contact no longer fills them in with the \
            rest of a form.
            """)
    }

    private var heldPhones: [CardExtra] {
        model.placement.onPrefill.filter { $0.kind == .phone }
    }

    private var prefillName: String {
        model.card.map(PrefillContact.name(for:)) ?? PrefillContact.searchName
    }

    private var chosenExtras: [CardExtra] {
        model.placement.onCard.filter(isChosen)
    }

    private var confirmMessage: String {
        let list = chosenExtras.map { "\($0.title): \($0.value)" }.joined(separator: "\n")
        return String(localized: "These come off your card and stay on \(prefillName):\n\(list)")
    }

    private func isChosen(_ extra: CardExtra) -> Bool {
        choices[extra.id] ?? model.placement.suggestedMoves.contains(extra)
    }

    private func chosen(_ extra: CardExtra) -> Binding<Bool> {
        Binding { isChosen(extra) } set: { choices[extra.id] = $0 }
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
