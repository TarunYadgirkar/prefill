#if PREFILL_TEST_BROWSERS
import Foundation
import PrefillKit
import Synchronization

// scripts/e2e-mac-chrome.sh runs a test build with a fixed card and its own store, so the
// browser check never needs a Contacts prompt answered or touches the person's card.
enum E2EFixture {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var store: (any SharedStore)? {
        environment["PREFILL_E2E_STORE"].map { AppGroupStore(directory: URL(filePath: $0)) }
    }

    static var gateway: FixtureGateway? {
        guard let path = environment["PREFILL_E2E_CARD"],
              let data = try? Data(contentsOf: URL(filePath: path)),
              let card = try? JSONDecoder().decode(CardRecord.self, from: data) else { return nil }
        return FixtureGateway(card: card)
    }
}

final class FixtureGateway: ContactsGateway {
    private let card: Mutex<CardRecord>

    init(card: CardRecord) {
        self.card = Mutex(card)
    }

    var link: CardLink {
        let current = card.withLock { $0 }
        return CardLink(
            contactIdentifier: current.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: current, snapshotAt: .now
        )
    }

    func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        let current = card.withLock { $0 }
        guard current.identifier == identifier else { throw .cardMissing }
        return current
    }

    func save(_ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String)
        throws(CardWriteFailure) -> CardSaveResult {
        card.withLock { $0 = target }
        return .saved
    }
}
#endif
