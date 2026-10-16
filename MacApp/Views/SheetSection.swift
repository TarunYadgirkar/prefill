import PrefillKit
import SwiftUI

// The person's Google Sheet. Each application sent from a browser here, or from the iPhone
// through iCloud, adds a row to it. Signing in with Google lets Prefill create the sheet itself;
// an Apps Script link already set up keeps working.
struct SheetSection: View {
    @Environment(MacModel.self) private var model
    @State private var isConnecting = false

    var body: some View {
        Section {
            if model.sheet.spreadsheet == nil, model.sheet.address == nil {
                Button(isConnecting ? "Waiting for Google…" : "Connect Google Sheets") {
                    isConnecting = true
                    Task {
                        await model.connectGoogle()
                        isConnecting = false
                    }
                }
                .disabled(isConnecting || GoogleAccount.client == nil)
            } else {
                if let spreadsheet = model.sheet.spreadsheet, spreadsheet.isValid {
                    Link("Open “\(GoogleSheets.title)”", destination: spreadsheet.url)
                }
                Toggle("Send applications", isOn: sendsApplications)
                LabeledContent("Waiting to send", value: model.sheet.waiting(model.applications).count.formatted())
                if let lastSent = model.sheet.lastSent {
                    LabeledContent("Last sent", value: lastSent.formatted(date: .abbreviated, time: .shortened))
                }
                HStack {
                    Button("Send now") { Task { await model.sendToSheet() } }
                        .disabled(!model.sheet.isOn)
                    Button("Disconnect", role: .destructive) { model.forgetSheet() }
                }
            }
        } header: {
            Text("Google Sheet")
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
    }

    private var footer: String {
        if let problem = model.sheetProblem, !problem.isEmpty { return problem }
        if model.sheet.spreadsheet != nil {
            return String(localized: """
                Applications from this Mac and your iPhone go to this sheet. Disconnecting leaves it in your Drive.
                """)
        }
        return String(localized: """
            Prefill creates a “Job Applications” sheet in your Google Drive and adds a row for every \
            application you send, from this Mac or your iPhone. It can only open the files it creates.
            """)
    }

    private var sendsApplications: Binding<Bool> {
        Binding { model.sheet.isOn } set: { model.setSheetOn($0) }
    }
}
