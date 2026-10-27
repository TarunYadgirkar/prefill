import Foundation
@testable import PrefillKit
import Testing

struct CloudMergedGatewayTests {
    private static let pronouns = CustomField(label: "Pronouns", value: "they/them", matchWords: [])
    private static let school = CustomField(label: "School", value: "UC Berkeley", matchWords: [])

    // Prefill's contact holds School; the copy also keeps Pronouns, from the other device.
    private struct Setup {
        let fake: FakeGateway
        let gateway: CloudMergedGateway
        let file: CloudCardCopyFile
    }

    private func setUp() throws -> Setup {
        let fake = FakeGateway(card: Alex.card.replacingCustomFields(with: [Self.school]))
        let file = CloudCardCopyFile(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        var copy = CloudCardCopy()
        let name = CloudCardCopy.recordName(.field(Self.pronouns))
        copy.merge([name: .init(body: .field(Self.pronouns), modifiedAt: .now)])
        try file.write(copy)
        return Setup(fake: fake, gateway: CloudMergedGateway(inner: fake, file: file) { _ in }, file: file)
    }

    @Test func aReadAddsWhatOnlyTheCopyKeeps() throws {
        let gateway = try setUp().gateway
        #expect(try gateway.fetchCard(identifier: "alex-card").customFields == [Self.school, Self.pronouns])
    }

    @Test func aSaveWritesTheContactAgainstWhatItHoldsAndLeavesCopyOnlyFieldsOut() throws {
        let setup = try setUp()
        let (fake, gateway) = (setup.fake, setup.gateway)
        let basis = try gateway.fetchCard(identifier: "alex-card")
        let extra = CardEntry(label: "home", payload: .email("alex.new@example.com"))
        let target = basis.replacing(.email, with: basis.emails + [extra])
        #expect(try gateway.save(target, basis: basis, transactionAuthor: "test") == .saved)
        #expect(fake.card.customFields == [Self.school])
        #expect(fake.card.emails.last == extra)
    }

    @Test func dropsAreStillRefusedAgainstTheMergedCard() throws {
        let gateway = try setUp().gateway
        let basis = try gateway.fetchCard(identifier: "alex-card")
        let target = basis.replacing(.email, with: Array(basis.emails.dropFirst()))
        #expect(throws: CardWriteFailure.other) { try gateway.save(target, basis: basis, transactionAuthor: "test") }
    }

    @Test func deletingACopyOnlyFieldInTheAppMarksItDeleted() throws {
        let setup = try setUp()
        let (fake, gateway, file) = (setup.fake, setup.gateway, setup.file)
        let basis = try gateway.fetchCard(identifier: "alex-card")
        let target = basis.replacingCustomFields(with: [Self.school])
        _ = try gateway.save(target, basis: basis, scope: .personEdit, transactionAuthor: "test")
        #expect(fake.card.customFields == [Self.school])
        #expect(try file.read().entries[CloudCardCopy.recordName(.field(Self.pronouns))]?.body == nil)
        #expect(try gateway.fetchCard(identifier: "alex-card").customFields == [Self.school])
    }

    @Test func aFieldDeletedFromTheContactIsNotAddedBackFromTheCopy() throws {
        let gateway = try setUp().gateway
        let basis = try gateway.fetchCard(identifier: "alex-card")
        #expect(basis.customFields.contains(Self.school))
        let target = basis.replacingCustomFields(with: [Self.pronouns])
        let result = try gateway.save(target, basis: basis, scope: .personEdit, transactionAuthor: "test")
        #expect(result == .saved)
        let after = try gateway.fetchCard(identifier: "alex-card")
        #expect(after.customFields == [Self.pronouns])
    }
}
