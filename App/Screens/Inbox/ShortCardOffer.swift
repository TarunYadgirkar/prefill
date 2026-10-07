import PrefillKit
import SwiftUI

// Shown once to someone whose card holds more than a name and phone: sharing the card sends
// all of it. Lists exactly what would move to Prefill's contact, which keeps offering it in
// forms. Nothing moves until the person taps the button under that list.
struct ShortCardOffer: View {
    // Setup moves on to its next step after either button.
    var onDone: () -> Void = {}
    @Environment(AppModel.self) private var model
    @State private var keptPhoneID: String?
    @State private var isWorking = false

    var body: some View {
        Section {
            Text("""
                Share Contact and AirDrop send everything on your card. Prefill can keep all but your name \
                and one phone number on its own contact, \(prefillName), and still offer it in every form.
                """)
            .textRole(.body)
            .accessibilityIdentifier("short-card-offer")
            if phones.count > 1 {
                Picker("Phone to keep", selection: keptPhone) {
                    ForEach(phones) { phone in
                        Text("\(phone.title): \(phone.value)").tag(phone.id)
                    }
                }
                .accessibilityIdentifier("short-card-phone")
            }
            ForEach(moves) { extra in
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(extra.title).textRole(.valueCaption)
                    Text(extra.value).textRole(.value)
                }
                .accessibilityElement(children: .combine)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) { buttons }
                VStack(alignment: .leading, spacing: Spacing.small) { buttons }
            }
            .controlSize(.small)
            .disabled(isWorking)
        } header: {
            Text("Keep your card short").textRole(.groupHeader)
        } footer: {
            Text("These \(moves.count) move off your card. You can put them back in Settings, Sharing your card.")
                .textRole(.footnote)
        }
    }

    @ViewBuilder private var buttons: some View {
        Button("Keep only name and phone on my card") {
            let chosen = moves
            isWorking = true
            Task {
                await model.moveOffCard(chosen)
                isWorking = false
                onDone()
            }
        }
        .prefillButtonStyle(.rowPrimary)
        .accessibilityIdentifier("short-card-keep")
        Button("Not now") {
            model.declineShortCard()
            onDone()
        }
            .prefillButtonStyle(.rowSecondary)
            .accessibilityIdentifier("short-card-not-now")
    }

    private var phones: [CardExtra] { model.placement.phonesOnCard }

    private var kept: CardExtra? {
        phones.first { $0.id == keptPhoneID } ?? phones.first
    }

    private var keptPhone: Binding<String?> {
        Binding { kept?.id } set: { keptPhoneID = $0 }
    }

    private var moves: [CardExtra] { model.placement.moves(keeping: kept) }

    private var prefillName: String {
        model.card.map(PrefillContact.name(for:)) ?? PrefillContact.searchName
    }
}
