import PrefillKit
import SwiftUI

// The two switches that change what Prefill does, then sharing, Safari's status and, under
// Advanced, what most people never need: sites it doesn't save on, the card link, restore
// and delete.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
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
                Section {
                    Toggle("Put the value you used on a site first", isOn: matchEachSite)
                        .accessibilityIdentifier("match-each-site")
                } footer: {
                    Text("When you pick a value on a site, Prefill offers it first there from then on.")
                        .textRole(.footnote)
                }
                Section {
                    NavigationLink {
                        SharingScreen()
                    } label: {
                        LabeledContent("Sharing your card", value: sharingStatus)
                    }
                    .disabled(model.card == nil)
                    .accessibilityIdentifier("sharing-your-card")
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
                SafariSection()
                Section {
                    NavigationLink {
                        KeyboardScreen()
                    } label: {
                        LabeledContent("Use Prefill in other apps", value: model.keyboardSeen == nil ? "" : "On")
                    }
                    .accessibilityIdentifier("use-in-other-apps")
                }
                AdvancedSection()
            }
            .navigationTitle("Settings")
            .screenTitleDisplay()
        }
    }

    private var sharingStatus: String {
        let count = model.placement.suggestedMoves.count
        if count > 0 { return String(localized: "\(count) to move") }
        return model.placement.isMinimal ? String(localized: "Name and phone") : ""
    }

    private var matchEachSite: Binding<Bool> {
        Binding { model.state.settings.matchEachSite } set: { model.setMatchEachSite($0) }
    }

    private var saveNewInfo: Binding<Bool> {
        Binding { model.state.settings.saveNewInfo } set: { model.setSaveNewInfo($0) }
    }
}

// Whether Safari runs the extension, since Prefill can't do anything until it does.
private struct SafariSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
    }

    private var safariSwitches: [SafariSwitch] {
        SafariSwitch.all(isEnabled: model.extensionEnabled == true, isAllowedOnWebsites: model.isAllowedOnWebsites)
    }
}

#Preview {
    SettingsScreen()
        .previewModel()
}
