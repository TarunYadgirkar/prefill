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
        let newer = SubmittedApplication(date: Date(timeIntervalSince1970: 2), request: Self.request)
        try archive.merge([older])
        try archive.merge([newer, older])
        #expect(try archive.read().map(\.id) == [newer.id, older.id])
        try archive.removeAll()
        #expect(try archive.read().isEmpty)
    }

    @Test func aDamagedArchiveIsNeverOverwritten() throws {
        let archive = temporaryArchive()
        try FileManager.default.createDirectory(at: archive.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: archive.url)
        #expect(throws: (any Error).self) {
            try archive.merge([SubmittedApplication(date: .now, request: Self.request)])
        }
        #expect(try Data(contentsOf: archive.url) == Data("not json".utf8))
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
