import PrefillKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingRestore = false
    @State private var isConfirmingDelete = false
    @State private var isChoosingCard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Reorder for each site", isOn: matchEachSite)
                        .accessibilityIdentifier("match-each-site")
                } footer: {
                    Text("Before you tap a field, Prefill puts the values you use on that site first.")
                        .textRole(.footnote)
                }
                Section {
                    Toggle("Save new info", isOn: saveNewInfo)
                        .accessibilityIdentifier("save-new-info")
                } footer: {
                    Text("""
                        Adds new emails, phone numbers and addresses you type into Safari forms to your card. \
                        When it’s off, they wait in your inbox.
                        """)
                    .textRole(.footnote)
                }
                if let line = model.intelligenceState.settingsLine {
                    Section {
                        Label {
                            Text(line).textRole(.body)
                        } icon: {
                            Image(systemName: "apple.intelligence")
                        }
                        .accessibilityIdentifier("apple-intelligence")
                    }
                }
                Section {
                    ForEach(safariSwitches) { item in
                        LabeledContent {
                            Text(item.setting)
                        } label: {
                            Label {
                                Text(item.title)
                            } icon: {
                                StatusMark(isDone: item.isDone)
                            }
                        }
                    }
                    Button {
                        Task { await SafariExtension.openSettings() }
                    } label: {
                        Label("Open Safari settings", systemImage: "arrow.up.forward.app")
                    }
                } header: {
                    Text("Safari").textRole(.groupHeader)
                }
                cardSection
                dataSection
            }
            .navigationTitle("Settings")
            .screenTitleDisplay()
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
    }

    private var cardSection: some View {
        Section {
            LabeledContent("Your card", value: model.cardName)
            NavigationLink {
                SharingScreen()
            } label: {
                LabeledContent("Sharing your card", value: sharingStatus)
            }
            .disabled(model.card == nil)
            .accessibilityIdentifier("sharing-your-card")
            NavigationLink("Sites") {
                SitesScreen()
            }
            .accessibilityIdentifier("sites")
            Button("Choose a different card") { isChoosingCard = true }
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
        } header: {
            Text("Contact card").textRole(.groupHeader)
        } footer: {
            Text("""
                Safari uses the card set as My Info under Settings, Apps, Safari, AutoFill. It's the same \
                card NameDrop and Share Contact send.
                """)
                .textRole(.footnote)
        }
    }

    private var dataSection: some View {
        Section {
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
        } footer: {
            Text("""
                Prefill keeps which card is yours, the sites you use each value on and recent saves \
                on this iPhone only.
                """)
            .textRole(.footnote)
        }
    }

    private var safariSwitches: [SafariSwitch] {
        SafariSwitch.all(isEnabled: model.extensionEnabled == true, isAllowedOnWebsites: model.isAllowedOnWebsites)
    }

    private var sharingStatus: String {
        let count = model.placement.suggestedMoves.count
        if count > 0 { return String(localized: "\(count) to move") }
        return model.placement.isMinimal ? String(localized: "Name and phone") : ""
    }

    private var restoreMessage: String {
        let date = model.state.cardLink?.snapshotAt.formatted(date: .long, time: .omitted) ?? ""
        let restored = String(localized: "Anything added to your card since \(date) comes off it.")
        guard model.placement.isMinimal else { return restored }
        return String(localized: """
            Emails, phone numbers and addresses on Prefill’s contact go back on your card first. \(restored)
            """)
    }

    private var matchEachSite: Binding<Bool> {
        Binding { model.state.settings.matchEachSite } set: { isOn in
            model.setMatchEachSite(isOn)
        }
    }

    private var saveNewInfo: Binding<Bool> {
        Binding { model.state.settings.saveNewInfo } set: { model.setSaveNewInfo($0) }
    }
}

#Preview {
    SettingsScreen()
        .previewModel()
}
