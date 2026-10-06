import AppKit
import PrefillKit
import SwiftUI

// What Prefill fills in first, then the switches, sharing and browsers, with the card and
// the switch for every app under Advanced.
struct SettingsView: View {
    @Environment(MacModel.self) private var model
    @State private var query = ""

    var body: some View {
        Form {
            YouSection(query: $query)
            CustomFieldsSection(query: query)
            Section {
                @Bindable var model = model
                Toggle("Save new info", isOn: $model.saveNewInfo)
                Toggle("Put the value you used on a site first", isOn: $model.matchEachSite)
                Toggle("Open at login", isOn: $model.opensAtLoginSetting)
            } footer: {
                Text("""
                    New emails, phone numbers and addresses you type are added to your card, or wait in the \
                    menu for you when Save new info is off. A value you pick on a site comes first there \
                    from then on.
                    """)
                .foregroundStyle(.secondary)
            }
            SharingSection()
            Section {
                BrowserList(browsers: model.browsers.filter(\.isInstalled))
                ExtensionFolder()
            } header: {
                Text("Browsers")
            }
            Section {
                CardStatus()
                AutofillSection()
            } header: {
                Text("Advanced")
            } footer: {
                Text("Prefill uses the card set as My Card in Contacts. iCloud keeps it in sync with your iPhone.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Size.settingsWidth, height: Size.settingsHeight)
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
