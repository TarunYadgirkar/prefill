import PrefillKit
import SwiftUI

// Pushed by value, so the sites list can push each site onto the same stack.
enum SettingsRoute: Hashable {
    case sites
}

// Sites, which card is the person's, and the two ways to undo Prefill: restore the card as it
// was when Prefill linked it, or forget everything Prefill keeps on this iPhone.
struct AdvancedSection: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingRestore = false
    @State private var isConfirmingDelete = false
    @State private var isChoosingCard = false

    var body: some View {
        Section {
            NavigationLink("Sites", value: SettingsRoute.sites)
            .accessibilityIdentifier("sites")
            LabeledContent("Your card", value: model.cardName)
            Button("Choose a different card") { isChoosingCard = true }
            restoreButton
            deleteButton
        } header: {
            Text("Advanced").textRole(.groupHeader)
        } footer: {
            Text("""
                Safari uses the card set as My Info under Settings, Apps, Safari, AutoFill, the same card \
                NameDrop and Share Contact send. Prefill keeps which card is yours, the sites you use each \
                value on and recent saves on this iPhone only.
                """)
            .textRole(.footnote)
        }
        .sheet(isPresented: $isChoosingCard) {
            NavigationStack {
                CardChooser(path: .constant([]))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isChoosingCard = false }
                        }
                    }
            }
        }
    }

    private var restoreButton: some View {
        Button("Restore original card", role: .destructive) { isConfirmingRestore = true }
            .disabled(model.state.cardLink == nil)
            .accessibilityIdentifier("restore-card")
            .confirmationDialog(
                "Restore your original card?", isPresented: $isConfirmingRestore, titleVisibility: .visible
            ) {
                Button("Restore original card", role: .destructive) {
                    Task { await model.restoreOriginalCard() }
                }
            } message: {
                Text(restoreMessage)
            }
    }

    private var deleteButton: some View {
        Button("Delete Prefill data", role: .destructive) { isConfirmingDelete = true }
            .accessibilityIdentifier("delete-data")
            .confirmationDialog(
                "Delete Prefill data?", isPresented: $isConfirmingDelete, titleVisibility: .visible
            ) {
                Button("Delete Prefill data", role: .destructive) {
                    Task { await model.deleteAllData() }
                }
            } message: {
                Text("Your contact card stays as it is. You’ll set Prefill up again.")
            }
    }

    private var restoreMessage: String {
        let date = model.state.cardLink?.snapshotAt.formatted(date: .long, time: .omitted) ?? ""
        let restored = String(localized: "Anything added to your card since \(date) comes off it.")
        guard model.placement.isMinimal else { return restored }
        return String(localized: """
            Emails, phone numbers and addresses on Prefill’s contact go back on your card first. \(restored)
            """)
    }
}
