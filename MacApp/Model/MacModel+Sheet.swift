import AuthenticationServices
import Foundation
import PrefillKit

// Sends each recorded application, from this Mac's browsers or from the iPhone through iCloud,
// to the person's Google Sheet: the one Prefill created after they signed in with Google
// (GoogleAccount), or the Apps Script web app they deployed (scripts/sheet/Code.gs). An
// application waits until the sheet takes it, so a failed send is retried on the next refresh.
extension MacModel {
    // Errors only: a Google error carries a status code, never a token.
    static let sheetLog = PrefillLog.logger("sheet")

    func sendToSheet() async {
        guard !isSendingToSheet, sheet.isOn, !sheet.waiting(applications).isEmpty else { return }
        isSendingToSheet = true
        defer { isSendingToSheet = false }
        do {
            let listed = try await sheet.spreadsheet == nil ? sendThroughScript() : sendToGoogle()
            sheet.listed.formUnion(listed)
            sheet.lastSent = .now
            sheetProblem = nil
            saveSheet()
        } catch {
            Self.sheetLog.error("sheet: \(String(describing: error), privacy: .public)")
            sheetProblem = Self.sheetMessage(error)
        }
    }

    private func sendThroughScript() async throws -> Set<UUID> {
        try await ApplicationSheet.send(applications, with: sheet) { try await URLSession.shared.data(for: $0).0 }
    }

    private func sendToGoogle() async throws -> Set<UUID> {
        guard let spreadsheet = sheet.spreadsheet, spreadsheet.isValid else { return [] }
        let waiting = sheet.waiting(applications)
        _ = try await google.send { GoogleSheets.appendRequest(waiting, to: spreadsheet.id, token: $0) }
        return Set(waiting.map(\.id))
    }

    // Signs in with Google, creates the "Job Applications" sheet in the person's Drive and sends
    // every application to it.
    func connectGoogle() async {
        do {
            try await google.signIn()
            let answer = try await google.send(GoogleSheets.createRequest)
            let created = try GoogleSheets.spreadsheet(from: answer)
            sheet = SheetSettings()
            sheet.spreadsheet = created
            sheet.isOn = true
            saveSheet()
            sheetProblem = nil
            await sendToSheet()
        } catch {
            Self.sheetLog.error("sheet: \(String(describing: error), privacy: .public)")
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
        sheet.isOn = isOn && (sheet.address != nil || sheet.spreadsheet != nil)
        saveSheet()
        if sheet.isOn { Task { await sendToSheet() } }
    }

    // The sheet itself stays in the person's Drive.
    func forgetSheet() {
        google.signOut()
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
        if error as? GoogleSheets.Failure == .signInNeeded {
            return String(localized: "Google needs you to sign in again. Choose Connect Google Sheets.")
        }
        if case GoogleSheets.Failure.refused(let status) = error {
            return String(localized: "Google turned the applications away (error \(status)). Prefill tries later.")
        }
        if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return "" }
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
