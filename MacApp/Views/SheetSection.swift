import PrefillKit
import SwiftUI

// The link to the person's Google Sheet. Each application sent from a browser here, or copied
// from the iPhone, then adds a row to it; one already there is skipped.
struct SheetSection: View {
    @Environment(MacModel.self) private var model
    @State private var link = ""
    @State private var isRefused = false

    var body: some View {
        Section {
            if model.sheet.address == nil {
                TextField("Web app link", text: $link, prompt: Text("https://script.google.com/macros/s/…/exec"))
                Button("Add link") { isRefused = !model.setSheetAddress(link) }
                    .disabled(link.isEmpty)
            } else {
                Toggle("Send applications", isOn: sendsApplications)
                LabeledContent("Waiting to send", value: model.sheet.waiting(model.applications).count.formatted())
                if let lastSent = model.sheet.lastSent {
                    LabeledContent("Last sent", value: lastSent.formatted(date: .abbreviated, time: .shortened))
                }
                HStack {
                    Button("Send now") { Task { await model.sendToSheet() } }
                        .disabled(!model.sheet.isOn)
                    Button("Remove link", role: .destructive) { model.forgetSheet() }
                }
            }
        } header: {
            Text("Google Sheet")
        } footer: {
            Text(model.sheetProblem ?? """
                Each application you send adds a row to your sheet. Get the link from the sheet’s Apps \
                Script after deploying Prefill’s script as a web app for Anyone, and keep it private.
                """)
            .foregroundStyle(.secondary)
        }
        .alert("That isn’t a web app link", isPresented: $isRefused) {
            Button("OK") {}
        } message: {
            Text("Paste the Web app URL from Deploy in your sheet’s Apps Script. It ends in /exec.")
        }
    }

    private var sendsApplications: Binding<Bool> {
        Binding { model.sheet.isOn } set: { model.setSheetOn($0) }
    }
}
