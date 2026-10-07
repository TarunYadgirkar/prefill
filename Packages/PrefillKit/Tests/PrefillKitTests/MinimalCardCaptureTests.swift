import Foundation
import Synchronization
import Testing
@testable import PrefillKit

// Saves the way CNContactStoreGateway does: through CardSplit, onto the card and Prefill's contact.
final class SplitGateway: ContactsGateway {
    let split: Mutex<CardSplit>

    init(_ split: CardSplit) {
        self.split = Mutex(split)
    }

    func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        split.withLock { $0.record }
    }

    func save(
        _ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        split.withLock { split in
            guard scope.allows(target, over: basis), split.record == basis else { return .stale(current: split.record) }
            let writes = split.writes(for: target)
            guard !writes.isEmpty else { return .unchanged }
            split = CardSplit(card: writes.card ?? split.card, copies: writes.extras.map { [$0] } ?? split.copies)
            return .saved
        }
    }
}

// Sharing a minimal card sends only the name and phone, so what forms save never lands on it.
struct MinimalCardCaptureTests {
    private let nameAndPhone = Alex.card.replacing(.email, with: []).replacing(.phone, with: [Alex.mobile.entry])
        .replacing(.address, with: [])

    @Test func aCaptureOnAMinimalCardGoesToPrefillsContact() throws {
        let moved = CardExtras(
            links: [], customFields: [], emails: Alex.card.emails, phones: [Alex.workPhone.entry],
            addresses: Alex.card.addresses, isMinimal: true
        )
        let gateway = SplitGateway(CardSplit(card: nameAndPhone, copies: [moved]))
        let link = CardLink(
            contactIdentifier: Alex.card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: Alex.card, snapshotAt: .daysAgo(30)
        )
        let store = MemoryStore(AppState(values: Alex.allValues, cardLink: link))
        let router = MessageRouter(store: store, gateway: gateway, now: { .testNow })
        let reply = router.route([
            "type": "capture", "host": "shop.example.net", "hasPassword": true, "trigger": "submit",
            "fields": [
                ["kind": "name", "userTyped": true, "value": "Alex Rivera", "autocomplete": "name"],
                ["kind": "email", "userTyped": true, "value": "alex.new@example.net", "autocomplete": "email"],
                ["kind": "phone", "userTyped": true, "value": "+1 (650) 555-0101", "autocomplete": "tel"]
            ]
        ])
        #expect(reply == .capture(CaptureResponse(saved: 2, review: 0, ignored: 1)))
        let after = gateway.split.withLock { $0 }
        #expect(after.card == nameAndPhone)
        #expect(after.extras?.emails.map(\.payload.display).last == "alex.new@example.net")
        #expect(after.extras?.phones.map(\.payload.display).last == "+1 (650) 555-0101")
        #expect(after.isMinimal)
    }
}
