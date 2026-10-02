import PrefillKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingRestore = false
    @State private var isChoosingCard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Match each site", isOn: matchEachSite)
                        .accessibilityIdentifier("match-each-site")
                } footer: {
                    Text("""
                        Before you tap a field, Prefill moves the values you use on that site to the front of \
                        your card. When it’s off, every site gets your own order.
                        """)
                }
                Section {
                    Toggle("Save new info", isOn: saveNewInfo)
                        .accessibilityIdentifier("save-new-info")
                } footer: {
                    Text("""
                        Adds new emails, phone numbers and addresses you type into Safari forms to your card. \
                        When it’s off, they wait in Recently added for you.
                        """)
                }
                Section("Safari") {
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
                }
                cardSection
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
            Text("Contact card")
        } footer: {
            Text("Safari uses the card set as My Info under Settings, Apps, Safari, AutoFill.")
        }
    }

    private var safariSwitches: [SafariSwitch] {
        SafariSwitch.all(isEnabled: model.extensionEnabled == true, isAllowedOnWebsites: model.isAllowedOnWebsites)
    }

    private var restoreMessage: String {
        let date = model.state.cardLink?.snapshotAt.formatted(date: .long, time: .omitted) ?? ""
        return String(localized: """
            Your card goes back to the emails, phone numbers and addresses it had on \(date). Anything added \
            since then comes off.
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
