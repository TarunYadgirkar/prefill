import Foundation
@testable import PrefillKit
import Testing

struct ApplicationSheetTests {
    private func application(_ host: String, _ path: String, _ title: String) -> SubmittedApplication {
        let request = ApplicationRequest(host: host, path: path, title: title, fields: [], files: [])
        return SubmittedApplication(date: Date(timeIntervalSince1970: 1_791_000_000), request: request)
    }

    @Test(arguments: [
        ("jobs.ashbyhq.com", "/hex/4502/application", "Product Engineer Intern @ Hex",
         "Hex", "Product Engineer Intern"),
        ("job-boards.greenhouse.io", "/affirm/jobs/1", "Job Application for Software Engineer Intern at Affirm",
         "Affirm", "Software Engineer Intern"),
        ("jobs.lever.co", "/kepler/2b9c/apply", "Kepler - Embedded Software Intern",
         "Kepler", "Embedded Software Intern"),
        ("nvidia.wd5.myworkdayjobs.com", "/en-US/apply", "Deep Learning Intern", "Nvidia", "Deep Learning Intern"),
        ("job-boards.greenhouse.io", "/five-rings/jobs/2", "Software Developer", "Five Rings", "Software Developer"),
        ("us-careers-rivian.icims.com",
         "/jobs/33832/software-engineering-intern---embedded-software-%28spring-2027-co-op%29/candidate",
         "Software Engineering Intern - Embedded Software (Spring 2027 Co-op) in Palo Alto, CA | Careers at Rivian",
         "Rivian", "Software Engineering Intern - Embedded Software (Spring 2027 Co-op)"),
        ("us-careers-rivian.icims.com",
         "/jobs/33832/software-engineering-intern---embedded-software-%28spring-2027-co-op%29/questions",
         "Application Questions - Software Engineering Intern - Embedded Software (Spring 2027 Co-op)",
         "Rivian", "Software Engineering Intern - Embedded Software (Spring 2027 Co-op)"),
        ("careers-acme.icims.com", "/jobs/12/data-analyst/candidate", "Candidate Profile | Careers at Acme",
         "Acme", "Data analyst"),
        ("www.gem.com", "/form", "Gen SWE Intern Interest Form", "Gem", "Gen SWE Intern Interest Form")
    ])
    func companyAndRoleComeFromTheTitleOrTheBoard(
        host: String, path: String, title: String, company: String, role: String
    ) {
        let (found, asked) = ApplicationSheet.companyAndRole(application(host, path, title))
        #expect(found == company)
        #expect(asked == role)
    }

    @Test func aRowMatchesTheSheetsColumns() {
        let row = ApplicationSheet.row(application("jobs.ashbyhq.com", "/hex/1", "Product Engineer Intern @ Hex"))
        #expect(row.cells.count == ApplicationSheet.columns.count)
        #expect(row.cells[1...4] == ["Hex", "Product Engineer Intern", "Internship", "Applied"])
        #expect(row.cells[6] == "Prefill: https://jobs.ashbyhq.com/hex/1")
        #expect(ApplicationSheet.kind("HackHarvard 2026 hackathon") == "Program")
        #expect(ApplicationSheet.kind("Software Engineer") == "Job")
    }

    @Test func onlyAnAppsScriptAddressIsAccepted() {
        #expect(ApplicationSheet.address(" https://script.google.com/macros/s/AKfy123/exec\n") != nil)
        #expect(ApplicationSheet.address("http://script.google.com/macros/s/AKfy123/exec") == nil)
        #expect(ApplicationSheet.address("https://example.com/macros/s/AKfy123/exec") == nil)
        #expect(ApplicationSheet.address("https://script.google.com/macros/s/AKfy123/dev") == nil)
    }

    @Test func applicationsTheSheetListsStopWaiting() throws {
        let sent = application("jobs.ashbyhq.com", "/hex/1", "Intern @ Hex")
        let new = application("jobs.lever.co", "/kepler/1", "Kepler - Intern")
        let reply = Data(#"{"added":["\#(sent.id.uuidString)"],"skipped":[]}"#.utf8)
        var settings = SheetSettings()
        settings.listed = try ApplicationSheet.listed(reply)
        #expect(settings.waiting([sent, new]) == [new])
        #expect(throws: ApplicationSheet.Failure.refused("No sheet")) {
            try ApplicationSheet.listed(Data(#"{"error":"No sheet"}"#.utf8))
        }
        #expect(throws: ApplicationSheet.Failure.unreadable) { try ApplicationSheet.listed(Data("<html>".utf8)) }
    }

    @Test func settingsLastUntilDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = SheetSettingsFile(directory: directory)
        var settings = SheetSettings()
        settings.isOn = true
        settings.address = ApplicationSheet.address("https://script.google.com/macros/s/AKfy123/exec")
        try file.write(settings)
        #expect(file.read() == settings)
        try file.removeAll()
        #expect(file.read() == SheetSettings())
    }
}

struct GoogleSheetsTests {
    private static let client = GoogleSheets.Client(id: "123-abc.apps.googleusercontent.com")!

    @Test func signInAsksOnlyForPrefillsOwnFilesAndChecksTheState() throws {
        let url = GoogleSheets.authorizationURL(client: Self.client, verifier: "v", state: "s1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "scope" }?.value == "https://www.googleapis.com/auth/drive.file")
        let redirect = items.first { $0.name == "redirect_uri" }?.value
        #expect(redirect == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        let back = try #require(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=s1&code=c"))
        #expect(GoogleSheets.code(from: back, state: "s1") == "c")
        #expect(GoogleSheets.code(from: back, state: "other") == nil)
        #expect(GoogleSheets.Client(id: "$(PREFILL_GOOGLE_CLIENT_ID)") == nil)
        let made = Data(
            #"{"spreadsheetId":"1a-B_c","spreadsheetUrl":"https://docs.google.com/spreadsheets/d/1a-B_c"}"#.utf8
        )
        #expect(try GoogleSheets.spreadsheet(from: made).id == "1a-B_c")
        let odd = Data(#"{"spreadsheetId":"../x","spreadsheetUrl":"https://docs.google.com/x"}"#.utf8)
        #expect(throws: GoogleSheets.Failure.unreadable) { try GoogleSheets.spreadsheet(from: odd) }
    }

    @Test func aRefreshKeepsTheRefreshTokenAndRowsUseTheSheetsColumns() throws {
        let data = Data(#"{"access_token":"a2","expires_in":3600}"#.utf8)
        let tokens = try GoogleSheets.tokens(from: data, keeping: "r1", now: Date(timeIntervalSince1970: 0))
        #expect(tokens.refreshToken == "r1")
        #expect(tokens.isFresh(at: Date(timeIntervalSince1970: 3000)))
        let application = SubmittedApplication(
            date: Date(timeIntervalSince1970: 1_760_000_000),
            request: ApplicationRequest(host: "jobs.ashbyhq.com", path: "/notion/apply", title: "Intern @ Notion",
                                        fields: [], files: [])
        )
        let request = GoogleSheets.appendRequest([application], to: "S", token: "a2")
        #expect(request.url?.path() == "/v4/spreadsheets/S/values/Applications!A1:append")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: [[String]]]
        #expect(body?["values"]?.first?[1] == "Notion")
    }
}
