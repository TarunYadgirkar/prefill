import CoreGraphics
import Foundation
import Testing
@testable import PrefillKit

// Built by `pnpm --dir web build`.
private let scriptURL = URL(filePath: #filePath)
    .deletingLastPathComponent().appending(path: "../../../../web/dist-mac/autofill.js").standardized

struct AutofillScriptTests {
    private func router() -> MessageRouter {
        let link = CardLink(
            contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: Alex.card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        return MessageRouter(store: store, gateway: FakeGateway(card: Alex.card), now: { .testNow })
    }

    private func script() throws -> AutofillScript {
        let source = try #require(try? String(contentsOf: scriptURL, encoding: .utf8), "run pnpm --dir web build")
        return try AutofillScript(source: source)
    }

    @Test func anEmailFieldGetsTheCardsEmails() throws {
        let rows = try script().rows(
            for: FieldDescription(tag: .input, label: "Email"), host: "example.com", router: router()
        )
        let emails: Set = ["alex.rivera@example.com", "alex@work.example.org", "alex.school@example.edu"]
        #expect(Set(rows.map(\.value)) == emails)
        #expect(rows.allSatisfy { $0.kind == "email" && $0.detail == "Email" })
    }

    @Test func aFullNameTextAreaGetsTheCardsName() throws {
        let rows = try script().rows(
            for: FieldDescription(tag: .textarea, label: "Full Name"), host: "airtable.com", router: router()
        )
        #expect(rows.map(\.value) == ["Alex Rivera"])
    }

    @Test func sensitiveAndSignInFieldsGetNothing() throws {
        let script = try script()
        #expect(script.rows(for: FieldDescription(tag: .input, label: "Card number"), host: "a.com", router: router())
            .isEmpty)
        #expect(script.rows(for: FieldDescription(tag: .input, label: "Email", signIn: true), host: "a.com",
                            router: router()).isEmpty)
    }
}

struct PanelGeometryTests {
    @Test func flipsAccessibilityFramesIntoAppKit() {
        let field = CGRect(x: 100, y: 200, width: 300, height: 30)
        #expect(PanelGeometry.appKitRect(fromAX: field, primaryHeight: 1000)
            == CGRect(x: 100, y: 770, width: 300, height: 30))
    }

    @Test func aDisplayAboveTheMainOneHasNegativeAccessibilityY() {
        let field = CGRect(x: 0, y: -500, width: 100, height: 20)
        #expect(PanelGeometry.appKitRect(fromAX: field, primaryHeight: 1000).minY == 1480)
    }

    @Test func sitsUnderTheFieldOrAboveItNearTheBottom() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 280, height: 200)
        let high = CGRect(x: 1300, y: 600, width: 200, height: 30)
        #expect(PanelGeometry.panelFrame(size: size, under: high, visible: visible)
            == CGRect(x: 1160, y: 396, width: 280, height: 200))
        let low = CGRect(x: 40, y: 50, width: 200, height: 30)
        #expect(PanelGeometry.panelFrame(size: size, under: low, visible: visible).minY == 84)
    }
}

struct RowFilterTests {
    private let rows = ["alex.rivera@example.com", "alex@work.example.org", "a.school@example.edu"]
        .map { AutofillRow(value: $0, detail: "Email", kind: "email") }

    @Test func narrowsToWhatIsTyped() {
        #expect(RowFilter.matching(rows, typed: "").count == 3)
        #expect(RowFilter.matching(rows, typed: "WORK").map(\.value) == ["alex@work.example.org"])
        #expect(RowFilter.matching(rows, typed: "zzz").isEmpty)
    }

    @Test func offersNothingOnceTheFieldHoldsAValue() {
        #expect(RowFilter.matching(rows, typed: "alex@work.example.org").isEmpty)
    }
}
