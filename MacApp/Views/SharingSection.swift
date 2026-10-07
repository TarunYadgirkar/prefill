import PrefillKit
import SwiftUI

// What is on My Card beyond the person's name and one phone number. Sharing the card sends
// it, so one button moves the exact list shown to Prefill's own contact, which keeps
// filling it in. What Prefill's contact holds can go back on the card one value at a time.
struct SharingSection: View {
    @Environment(MacModel.self) private var model
    @State private var keptPhoneID: String?

    var body: some View {
        Section {
            if moves.isEmpty {
                Label("My Card holds only your name and phone number", systemImage: "checkmark.circle")
            } else {
                if phones.count > 1 {
                    Picker("Phone to keep", selection: keptPhone) {
                        ForEach(phones) { phone in
                            Text("\(phone.title): \(phone.value)").tag(phone.id)
                        }
                    }
                }
                ForEach(moves) { extra in
                    LabeledContent(extra.title, value: extra.value)
                }
                Button("Keep only name and phone on my card") {
                    let chosen = moves
                    Task { await model.moveOffCard(chosen) }
                }
            }
        } header: {
            Text("Sharing your card")
        } footer: {
            Text(moves.isEmpty ? keptFooter : moveFooter)
                .foregroundStyle(.secondary)
        }
        if !held.isEmpty {
            Section("On \(prefillName)") {
                ForEach(held) { extra in
                    LabeledContent(extra.title) {
                        HStack {
                            Text(extra.value)
                            Button("Put back on card") {
                                Task { await model.putOnCard(extra) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var phones: [CardExtra] {
        model.placement.isMinimal ? [] : model.placement.phonesOnCard
    }

    private var kept: CardExtra? {
        phones.first { $0.id == keptPhoneID } ?? phones.first
    }

    private var keptPhone: Binding<String?> {
        Binding { kept?.id } set: { keptPhoneID = $0 }
    }

    // On a minimal card every phone still on it stays; otherwise the one the person keeps.
    private var moves: [CardExtra] {
        model.placement.isMinimal ? model.placement.suggestedMoves : model.placement.moves(keeping: kept)
    }

    // Emails, phones and addresses Prefill's contact holds. Links and custom answers stay there.
    private var held: [CardExtra] {
        model.placement.onPrefill.filter { $0.kind.map { $0 != .link } ?? false }
    }

    private var prefillName: String {
        model.card.map(PrefillContact.name(for:)) ?? PrefillContact.searchName
    }

    private var moveFooter: String {
        """
        Share Contact and AirDrop send everything on My Card. These \(moves.count) move to \(prefillName), \
        and Prefill still fills them in.
        """
    }

    private var keptFooter: String {
        """
        Prefill keeps everything else on its own contact, \(prefillName), and fills it in from there. \
        NameDrop sends your name and the number you pick.
        """
    }
}
