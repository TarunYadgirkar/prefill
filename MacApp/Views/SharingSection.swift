import PrefillKit
import SwiftUI

// Links and custom fields still on My Card. Sharing the card sends them, so the person can
// move them to Prefill's own contact, which keeps filling them in. Nothing moves until they
// confirm the exact list.
struct SharingSection: View {
    @Environment(MacModel.self) private var model
    @State private var isConfirming = false

    var body: some View {
        Section {
            if model.extrasOnCard.isEmpty {
                Label("Your links and custom fields are off My Card", systemImage: "checkmark.circle")
            } else {
                ForEach(model.extrasOnCard) { extra in
                    LabeledContent(extra.title, value: extra.value)
                }
                Button("Move \(model.extrasOnCard.count) off My Card…") { isConfirming = true }
                    .confirmationDialog(
                        "Move \(model.extrasOnCard.count) off My Card?", isPresented: $isConfirming
                    ) {
                        Button("Move off My Card") {
                            Task { await model.moveOffCard(model.extrasOnCard) }
                        }
                    } message: {
                        Text("They come off My Card and stay on \(prefillName), so Prefill still fills them in.")
                    }
            }
        } header: {
            Text("Sharing your card")
        } footer: {
            Text("""
                NameDrop sends only your name, Contact Poster and the number or email you pick. Sharing \
                My Card any other way sends everything on it, so Prefill keeps links and custom fields on \
                its own contact, \(prefillName).
                """)
            .foregroundStyle(.secondary)
        }
    }

    private var prefillName: String {
        model.card.map(PrefillContact.name(for:)) ?? PrefillContact.searchName
    }
}
