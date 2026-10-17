import Foundation
@testable import PrefillKit
import Testing

struct ApplicationTests {
    private static let request = ApplicationRequest(
        host: "jobs.lever.co", path: "/kepler/2b9c/apply", title: "Kepler - Embedded Software Intern",
        fields: [
            .init(question: "Expected graduation", answer: "May 2028"),
            .init(question: "Why Kepler?", answer: "=I like \"space\",\nand radios.")
        ],
        files: [.init(question: "Resume/CV", name: "Resume_Fall_2026.pdf")]
    )

    private static let other = ApplicationRequest(
        host: "jobs.ashbyhq.com", path: "/openai/apply", title: "OpenAI", fields: [.init(question: "q", answer: "a")],
        files: []
    )

    private func temporaryArchive() -> ApplicationArchive {
        ApplicationArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func aSentApplicationWaitsInTheEventsAndTouchesNothingElse() throws {
        let store = InMemoryStore()
        let router = MessageRouter(store: store, gateway: FakeGateway(card: Alex.card))
        let data = try JSONEncoder().encode(ExtensionRequest.application(Self.request))
        let reply = router.route(try JSONSerialization.jsonObject(with: data))
        #expect(reply == .application(ApplicationResponse(saved: true)))
        let queued = (try? store.readEvents().applications) ?? []
        #expect(queued.map(\.fields) == [Self.request.fields])
        #expect((try? store.readEvents().captures) == [])
    }

    @Test func theArchiveKeepsEveryApplicationOnceNewestFirst() throws {
        let archive = temporaryArchive()
        let older = SubmittedApplication(date: Date(timeIntervalSince1970: 1), request: Self.request)
        let newer = SubmittedApplication(date: Date(timeIntervalSince1970: 2), request: Self.other)
        let resent = SubmittedApplication(date: Date(timeIntervalSince1970: 3), request: Self.request)
        try archive.merge([older])
        try archive.merge([newer, older])
        #expect(try archive.read().map(\.id) == [newer.id, older.id])
        try archive.merge([resent])
        #expect(try archive.read().map(\.date) == [resent.date, newer.date])
    }

    @Test func aDeletedApplicationNeverComesBackFromAnotherCopy() throws {
        let archive = temporaryArchive()
        let kept = SubmittedApplication(date: Date(timeIntervalSince1970: 1), request: Self.request)
        let deleted = SubmittedApplication(date: Date(timeIntervalSince1970: 2), request: Self.other)
        try archive.merge([kept, deleted])
        #expect(try archive.remove([deleted.id]).map(\.id) == [kept.id])
        try archive.merge([deleted])
        #expect(try archive.read().map(\.id) == [kept.id])
        try archive.removeAll()
        try archive.merge([deleted])
        #expect(try archive.read().map(\.id) == [deleted.id])
    }

    @Test func theStepsOfOneApplicationBecomeOneRecord() throws {
        let archive = temporaryArchive()
        let id = UUID()
        let contact = ApplicationRequest(
            id: id, host: "account.amazon.jobs", path: "/apply/1", title: "Contact",
            fields: [.init(question: "Phone", answer: "925-555-0100"), .init(question: "School", answer: "Cal")],
            files: []
        )
        let education = ApplicationRequest(
            id: id, host: "account.amazon.jobs", path: "/apply/2", title: "Education",
            fields: [
                .init(question: "School", answer: "UC Berkeley"), .init(question: "Graduation", answer: "May 2028")
            ],
            files: [.init(question: "Resume", name: "Resume_Fall.pdf")]
        )
        try archive.merge([SubmittedApplication(date: Date(timeIntervalSince1970: 1), request: contact)])
        let merged = try archive.merge([SubmittedApplication(date: Date(timeIntervalSince1970: 2), request: education)])
        #expect(merged.count == 1)
        #expect(merged.first?.fields.map(\.answer) == ["925-555-0100", "UC Berkeley", "May 2028"])
        #expect(merged.first?.files.map(\.name) == ["Resume_Fall.pdf"])
        #expect(merged.first?.path == "/apply/2")
        try archive.removeAll()
        #expect(try archive.read().isEmpty)
    }

    @Test func aQuestionAskedTwiceKeepsBothAnswers() {
        let id = UUID()
        let jobs: [ApplicationRequest.Field] = [
            .init(question: "Employer", answer: "Hex"), .init(question: "Employer", answer: "Gem")
        ]
        let first = SubmittedApplication(date: .now, request: ApplicationRequest(
            id: id, host: "a.jobs", path: "/", title: "A", fields: jobs, files: []
        ))
        let again = first.adding(first)
        #expect(again.fields.map(\.answer) == ["Hex", "Gem"])
    }

    @Test func aDamagedArchiveIsNeverOverwritten() throws {
        let archive = temporaryArchive()
        let folder = archive.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: archive.url)
        #expect(throws: (any Error).self) {
            try archive.merge([SubmittedApplication(date: .now, request: Self.request)])
        }
        #expect(try Data(contentsOf: archive.url) == Data("not json".utf8))
    }

    @Test func aCopiedFileKeepsOnlyApplicationsAPageCouldSend() throws {
        let good = SubmittedApplication(date: .now, request: Self.request)
        let forged = SubmittedApplication(date: .now, request: ApplicationRequest(
            host: "Evil Host/", path: "/", title: "x", fields: [.init(question: "q", answer: "a")], files: []
        ))
        let data = try JSONEncoder().encode([good, forged])
        let copied = try ApplicationArchive.applications(from: data)
        #expect(copied.kept.map(\.id) == [good.id])
        #expect(copied.refused == 1)
    }

    @Test func aCopiedFileKeepsARecordCombinedFromManySteps() throws {
        let id = UUID()
        let steps = (0..<3).map { step in
            SubmittedApplication(date: Date(timeIntervalSince1970: Double(step)), request: ApplicationRequest(
                id: id, host: "account.amazon.jobs", path: "/apply/\(step)", title: "Step \(step)",
                fields: (0..<25).map { .init(question: "Question \(step)-\($0)", answer: "Answer") },
                files: (0..<2).map { .init(question: "File \(step)-\($0)", name: "file\(step)-\($0).pdf") }
            ))
        }
        let combined = SubmittedApplication.combined(steps)
        #expect(combined.map(\.fields.count) == [75])
        let copied = try ApplicationArchive.applications(from: JSONEncoder().encode(combined))
        #expect(copied.kept.map(\.fields.count) == [75])
        #expect(copied.refused == 0)
        let payload = try #require(ApplicationCloudRecord.payload(combined[0]))
        let name = ApplicationCloudRecord.recordName(id)
        let record = ApplicationCloudRecord.application(recordName: name, payload: payload)
        #expect(record?.fields.count == 75)
    }

    @Test func anArchiveInTodaysFormatStillReads() throws {
        let json = """
        [{"date":800000000,"fields":[{"answer":"May 2028","question":"Expected graduation"}],
        "files":[{"name":"Resume.pdf","question":"Resume/CV"}],"host":"jobs.lever.co",
        "id":"6F1C2A9E-3B4D-4E5F-8A6B-7C8D9E0F1A2B","path":"/kepler/apply","title":"Kepler"}]
        """
        let copied = try ApplicationArchive.applications(from: Data(json.utf8))
        #expect(copied.kept.map(\.title) == ["Kepler"])
        let archive = temporaryArchive()
        let folder = archive.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: archive.url)
        #expect(try archive.read().map(\.fields.count) == [1])
    }

    @Test func theStepsOfOneApplicationTakeOneSlotInTheQueue() {
        let id = UUID()
        let others = (0..<ExtensionEvents.maxApplications).map { index in
            SubmittedApplication(date: Date(timeIntervalSince1970: Double(index)), request: Self.other)
        }
        let first = SubmittedApplication(date: Date(timeIntervalSince1970: 0), request: ApplicationRequest(
            id: id, host: "account.amazon.jobs", path: "/apply/1", title: "Contact",
            fields: [.init(question: "Phone", answer: "925-555-0100")], files: []
        ))
        var events = ExtensionEvents(applications: [first])
        for step in 2...6 {
            events = events.appending(ExtensionEvents(applications: [SubmittedApplication(
                date: Date(timeIntervalSince1970: Double(step)), request: ApplicationRequest(
                    id: id, host: "account.amazon.jobs", path: "/apply/\(step)", title: "Step \(step)",
                    fields: [.init(question: "Question \(step)", answer: "Answer")], files: []
                )
            )]))
        }
        #expect(events.applications.count == 1)
        #expect(events.applications.first?.fields.count == 6)
        let later = others.map { SubmittedApplication(date: $0.date.addingTimeInterval(10), request: ApplicationRequest(
            host: "jobs.ashbyhq.com", path: "/a", title: "A", fields: [.init(question: "q", answer: "a")], files: []
        )) }
        let room = Array(later.prefix(ExtensionEvents.maxApplications - 1))
        let full = events.appending(ExtensionEvents(applications: room))
        #expect(full.applications.count == ExtensionEvents.maxApplications)
        #expect(full.applications.contains { $0.id == id })
    }

    @Test func theCSVHasARowPerQuestionAndNoFormulas() {
        let application = SubmittedApplication(date: Date(timeIntervalSince1970: 86_400 * 365), request: Self.request)
        let lines = ApplicationExport.csv([application]).components(separatedBy: "\r\n")
        #expect(lines[0] == "Date,Company or role,Site,Page,Question,Answer,Files")
        #expect(lines[1].hasSuffix("Expected graduation,May 2028,Resume_Fall_2026.pdf"))
        #expect(lines[2].contains(#"Why Kepler?,"'=I like ""space"","#))
        #expect(lines[1].contains("lever.co,https://jobs.lever.co/kepler/2b9c/apply"))
    }
}

struct ApplicationCloudRecordTests {
    private static let application = SubmittedApplication(
        date: Date(timeIntervalSince1970: 1_760_000_000),
        request: ApplicationRequest(
            host: "jobs.lever.co", path: "/kepler/apply", title: "Kepler",
            fields: [.init(question: "Why Kepler?", answer: "Radios.")], files: []
        )
    )

    @Test func aRecordReadsBackAsTheSameApplication() throws {
        let payload = try #require(ApplicationCloudRecord.payload(Self.application))
        let name = ApplicationCloudRecord.recordName(Self.application.id)
        #expect(ApplicationCloudRecord.application(recordName: name, payload: payload) == Self.application)
    }

    @Test func aRecordUnderAnotherNameOrBrokenIsRefused() throws {
        let payload = try #require(ApplicationCloudRecord.payload(Self.application))
        #expect(ApplicationCloudRecord.application(recordName: UUID().uuidString, payload: payload) == nil)
        let name = ApplicationCloudRecord.recordName(Self.application.id)
        #expect(ApplicationCloudRecord.application(recordName: name, payload: Data("{".utf8)) == nil)
    }
}

struct StoreMigrationTests {
    @Test func theKeychainStoreMovesIntoAnEmptyAppGroupOnce() throws {
        let old = InMemoryStore()
        let new = InMemoryStore()
        let state = AppState(settings: Settings(matchEachSite: false))
        try old.writeAppState(state)
        try old.appendEvents(usage: [UsageEvent(valueID: UUID(), host: "example.org", date: .now)], captures: [])
        StoreMigration.adopt(from: old, into: new)
        #expect(try new.readAppState() == state)
        #expect(try new.readEvents().usage.count == 1)
        #expect(try old.readAppState() == AppState())
    }

    @Test func anAppGroupWithItsOwnStateIsLeftAlone() throws {
        let old = InMemoryStore()
        let new = InMemoryStore()
        try old.writeAppState(AppState(settings: Settings(matchEachSite: false)))
        let current = AppState(settings: Settings(saveNewInfo: false))
        try new.writeAppState(current)
        StoreMigration.adopt(from: old, into: new)
        #expect(try new.readAppState() == current)
        #expect(try old.readAppState() != AppState())
    }
}

struct CloudCardCopyTests {
    private static let field = CustomField(label: "Pronouns", value: "they/them", matchWords: [])
    private static let link = CardEntry(label: "LinkedIn", payload: .link("https://linkedin.com/in/alex"))

    private static func card(fields: [CustomField], links: [CardEntry]) -> CardRecord {
        CardRecord(
            identifier: "me", givenName: "Alex", familyName: "Rivera", emails: [], phones: [], addresses: [],
            links: links, customFields: fields
        )
    }

    @Test func aFieldThatLeavesTheContactBecomesATombstone() {
        var extras = CloudCardCopy()
        let start = Date(timeIntervalSince1970: 1)
        #expect(extras.mirror(Self.card(fields: [Self.field], links: [Self.link]), now: start).count == 2)
        #expect(extras.mirror(Self.card(fields: [Self.field], links: [Self.link]), now: start).isEmpty)
        let changed = extras.mirror(Self.card(fields: [], links: [Self.link]), now: start.addingTimeInterval(1))
        #expect(changed == [CloudCardCopy.recordName(.field(Self.field))])
        #expect(extras.entries[changed[0]]?.body == nil)
    }

    @Test func anEntryFromTheOtherDeviceSurvivesUntilItReachesThisContact() {
        var extras = CloudCardCopy()
        let name = CloudCardCopy.recordName(.field(Self.field))
        extras.merge([name: .init(body: .field(Self.field), modifiedAt: Date(timeIntervalSince1970: 5))])
        let changed = extras.mirror(Self.card(fields: [], links: [Self.link]), now: Date(timeIntervalSince1970: 6))
        #expect(changed.count == 1)
        #expect(extras.entries[name]?.body == .field(Self.field))
    }

    @Test func aDeletionFromTheOtherDeviceIsNotUndoneByThisContact() {
        var extras = CloudCardCopy()
        let card = Self.card(fields: [Self.field], links: [])
        _ = extras.mirror(card, now: Date(timeIntervalSince1970: 1))
        let name = CloudCardCopy.recordName(.field(Self.field))
        extras.merge([name: .init(body: nil, modifiedAt: Date(timeIntervalSince1970: 2))])
        #expect(extras.mirror(card, now: Date(timeIntervalSince1970: 3)).isEmpty)
        #expect(extras.entries[name]?.body == nil)
    }

    @Test func anOlderChangeFromTheOtherDeviceLoses() throws {
        var extras = CloudCardCopy()
        _ = extras.mirror(Self.card(fields: [Self.field], links: []), now: Date(timeIntervalSince1970: 10))
        let name = CloudCardCopy.recordName(.field(Self.field))
        extras.merge([name: .init(body: nil, modifiedAt: Date(timeIntervalSince1970: 5))])
        #expect(extras.entries[name]?.body == .field(Self.field))
        let entry = try #require(extras.entries[name])
        let payload = try #require(CloudCardCopyFile.payload(entry))
        #expect(CloudCardCopyFile.entry(recordName: name, payload: payload) == extras.entries[name])
        #expect(CloudCardCopyFile.entry(recordName: "f-other", payload: payload) == nil)
    }
}
