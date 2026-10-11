import Foundation
import PrefillKit

// Sends each recorded application to the person's Google Sheet, through the Apps Script web
// app they deployed from it (scripts/sheet/Code.gs). Nothing is sent until they add its link.
// An application waits until the sheet answers that it lists it, so a failed send is retried
// the next time the app reads the store.
extension MacModel {
    func sendToSheet() async {
        guard !isSendingToSheet, sheet.isOn, !sheet.waiting(applications).isEmpty else { return }
        isSendingToSheet = true
        defer { isSendingToSheet = false }
        do {
            let listed = try await ApplicationSheet.send(applications, with: sheet) {
                try await URLSession.shared.data(for: $0).0
            }
            sheet.listed.formUnion(listed)
            sheet.lastSent = .now
            sheetProblem = nil
            saveSheet()
        } catch {
            sheetProblem = Self.sheetMessage(error)
        }
    }

    // A link that isn't an Apps Script web app's is refused, and nothing changes.
    func setSheetAddress(_ text: String) -> Bool {
        guard let address = ApplicationSheet.address(text) else { return false }
        sheet.address = address
        sheet.isOn = true
        saveSheet()
        Task { await sendToSheet() }
        return true
    }

    func setSheetOn(_ isOn: Bool) {
        sheet.isOn = isOn && sheet.address != nil
        saveSheet()
        if sheet.isOn { Task { await sendToSheet() } }
    }

    func forgetSheet() {
        sheet = SheetSettings()
        sheetProblem = nil
        try? sheetFile.removeAll()
    }

    private func saveSheet() {
        do {
            try sheetFile.write(sheet)
        } catch {
            sheetProblem = String(localized: "Prefill couldn’t save the sheet setting. Try again in a moment.")
        }
    }

    private static func sheetMessage(_ error: any Error) -> String {
        if case ApplicationSheet.Failure.refused(let reason) = error {
            return String(localized: "The sheet turned the applications away: \(reason)")
        }
        if error is ApplicationSheet.Failure {
            return String(localized: """
                The link didn’t answer like Prefill’s script. Check that it’s the web app link from Deploy, \
                with access for Anyone.
                """)
        }
        return String(localized: "Prefill couldn’t reach Google. It tries again the next time it opens.")
    }
}
