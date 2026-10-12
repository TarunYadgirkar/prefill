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
