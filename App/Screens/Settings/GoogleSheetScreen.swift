import PrefillKit
import SwiftUI

// Where the link to the person's Google Sheet goes. Each application they send then adds a row
// to it; one already there is skipped.
struct GoogleSheetScreen: View {
    @Environment(AppModel.self) private var model
    @State private var link = ""
    @State private var isRefused = false

    var body: some View {
        Form {
            Section {
                Text("""
                    Each job application you send adds a row to your Google Sheet: date, company, role and \
                    the page you applied on. An application the sheet already lists is skipped.
                    """)
                .textRole(.body)
            }
            if model.sheet.address == nil { linkSection } else { statusSection }
        }
        .navigationTitle("Google Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .alert("That isn’t a web app link", isPresented: $isRefused) {
            Button("OK") {}
        } message: {
            Text("Paste the Web app URL from Deploy in your sheet’s Apps Script. It ends in /exec.")
        }
    }

    private var linkSection: some View {
        Section {
            TextField("https://script.google.com/macros/s/…/exec", text: $link)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("sheet-link")
            Button("Add link") { isRefused = !model.setSheetAddress(link) }
                .disabled(link.isEmpty)
        } header: {
            Text("Web app link").textRole(.groupHeader)
        } footer: {
            Text("""
                In the sheet, open Extensions, Apps Script, paste Prefill’s script and deploy it as a web \
                app that runs as you, for Anyone. Keep the link private: anyone with it can add rows.
                """)
            .textRole(.footnote)
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("Send applications", isOn: sendsApplications)
                .accessibilityIdentifier("sheet-on")
            LabeledContent("Waiting to send", value: model.sheet.waiting(model.applications).count.formatted())
            if let lastSent = model.sheet.lastSent {
                LabeledContent("Last sent", value: lastSent.formatted(date: .abbreviated, time: .shortened))
            }
            Button("Send now") { Task { await model.sendToSheet() } }
                .disabled(!model.sheet.isOn)
            Button("Remove link", role: .destructive) { model.forgetSheet() }
        } footer: {
            if let problem = model.sheetProblem {
                Text(problem).textRole(.footnote).foregroundStyle(Palette.attention)
            }
        }
    }

    private var sendsApplications: Binding<Bool> {
        Binding { model.sheet.isOn } set: { model.setSheetOn($0) }
    }
}
