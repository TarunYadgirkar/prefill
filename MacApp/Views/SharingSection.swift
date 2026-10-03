import PrefillKit
import SwiftUI

// What is still on My Card beyond the person's name and phone number. Sharing the card sends
// it, so the person can move it to Prefill's own contact, which keeps filling it in. Nothing
// moves until they confirm the exact list.
struct SharingSection: View {
    @Environment(MacModel.self) private var model
    @State private var isConfirming = false

    var body: some View {
        Section {
            if moves.isEmpty {
                Label("My Card holds only your name and phone number", systemImage: "checkmark.circle")
            } else {
                ForEach(moves) { extra in
                    LabeledContent(extra.title, value: extra.value)
                }
                Button("Move \(moves.count) off My Card…") { isConfirming = true }
                    .confirmationDialog("Move \(moves.count) off My Card?", isPresented: $isConfirming) {
                        Button("Move off My Card") {
                            Task { await model.moveOffCard(moves) }
                        }
                    } message: {
                        Text("""
                            They come off My Card and stay on \(prefillName), so Prefill still fills them in. \
                            On iPhone, Safari then shows emails and addresses as Prefill’s suggestions, at most 3, \
                            and AutoFill Contact no longer fills them in with the rest of a form.
                            """)
                    }
            }
        } header: {
            Text("Sharing your card")
        } footer: {
            Text("""
                NameDrop sends only your name, Contact Poster and the number or email you pick, so pick your \
                phone number. Sharing My Card any other way sends everything on it, so Prefill can keep all \
                but your name and first phone number on its own contact, \(prefillName).
                """)
            .foregroundStyle(.secondary)
        }
    }

    private var moves: [CardExtra] { model.placement.suggestedMoves }

    private var prefillName: String {
        model.card.map(PrefillContact.name(for:)) ?? PrefillContact.searchName
    }
}
