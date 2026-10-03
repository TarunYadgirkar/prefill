import AppKit
import PrefillKit
import SwiftUI

struct SettingsView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        Form {
            Section {
                CardStatus()
            } header: {
                Text("Contact card")
            } footer: {
                Text("Prefill uses the card set as My Card in Contacts. iCloud keeps it in sync with your iPhone.")
                    .foregroundStyle(.secondary)
            }
            Section {
                @Bindable var model = model
                Toggle("Reorder for each site", isOn: $model.matchEachSite)
                Toggle("Save new info", isOn: $model.saveNewInfo)
                Toggle("Open at login", isOn: $model.opensAtLoginSetting)
            } footer: {
                Text("""
                    Chrome and Arc suggest the values you use on each site first. New emails, phone numbers \
                    and addresses you type are added to your card, or wait in the menu for you when Save new \
                    info is off.
                    """)
                .foregroundStyle(.secondary)
            }
            CustomFieldsSection()
            Section {
                BrowserList(browsers: model.browsers.filter(\.isInstalled))
                ExtensionFolder()
            } header: {
                Text("Browsers")
            }
        }
        .formStyle(.grouped)
        .frame(width: Size.settingsWidth)
        .alert("Prefill", isPresented: problemShown) {
            Button("OK") { model.problem = nil }
        } message: {
            Text(model.problem ?? "")
        }
    }

    private var problemShown: Binding<Bool> {
        Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })
    }
}

// Where the browser extension lives inside the app, for Load unpacked.
struct ExtensionFolder: View {
    static var url: URL {
        Bundle.main.resourceURL?.appending(path: "ChromeExtension", directoryHint: .isDirectory)
            ?? Bundle.main.bundleURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("""
                Add the extension once in each browser: open chrome://extensions (in Arc, arc://extensions), \
                turn on Developer mode, choose Load unpacked, press Command-Shift-G and paste the folder path.
                """)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Copy folder path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.url.path(percentEncoded: false), forType: .string)
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Self.url]) }
            }
        }
    }
}
