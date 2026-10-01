import Foundation
import PrefillKit
import SwiftUI
import Synchronization

// Sample data for SwiftUI previews only. It mirrors testbed/alex-rivera.vcf.
nonisolated enum PreviewData {
    static let created = Date(timeIntervalSince1970: 1_790_000_000)

    static let emails = [
        value(.email("alex.rivera@example.com"), "_$!<Home>!$_"),
        value(.email("alex@work.example.org"), "_$!<Work>!$_"),
        value(.email("alex.school@example.edu"), nil)
    ]
    static let phones = [
        value(.phone("+1 (510) 555-0134"), "_$!<Mobile>!$_"),
        value(.phone("+1 (415) 555-0199"), "_$!<Work>!$_")
    ]
    static let addresses = [
        value(.address(PostalAddress(
            street: "2400 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94704", country: "United States"
        )), "_$!<Home>!$_"),
        value(.address(PostalAddress(
            street: "1 Market St Suite 300", city: "San Francisco", state: "CA", postalCode: "94105",
            country: "United States"
        )), "_$!<Work>!$_")
    ]

    static let card = CardRecord(
        identifier: "preview-card", givenName: "Alex", familyName: "Rivera",
        emails: emails.map(\.entry), phones: phones.map(\.entry), addresses: addresses.map(\.entry)
    )

    static let events = ExtensionEvents(
        usage: [
            UsageEvent(valueID: emails[1].id, host: "portal.example.org", date: .now.addingTimeInterval(-86_400)),
            UsageEvent(
                valueID: emails[2].id, host: "fernhill-library.example", date: .now.addingTimeInterval(-3 * 86_400)
            )
        ],
        captures: [
            Capture(
                host: "bluebird-tickets.example", value: value(.phone("+1 (510) 555-0172"), nil),
                date: .now.addingTimeInterval(-7_200), verdict: .needsReview
            )
        ]
    )

    static func value(_ payload: ContactPayload, _ label: String?) -> ContactValue {
        ContactValue(payload: payload, label: label, source: .card, createdAt: created)
    }

    static func link(_ card: CardRecord = card) -> CardLink {
        CardLink(
            contactIdentifier: card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: created
        )
    }
}

extension ContactValue {
    nonisolated var entry: CardEntry { CardEntry(label: label, payload: payload) }
}

nonisolated final class PreviewGateway: ContactsGateway {
    private let card: Mutex<CardRecord>

    init(card: CardRecord = PreviewData.card) {
        self.card = Mutex(card)
    }

    func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        card.withLock { $0 }
    }

    func save(
        _ target: CardRecord, basis: CardRecord, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        card.withLock { $0 = target }
        return .saved
    }
}

nonisolated struct PreviewContacts: ContactsSource {
    var access: ContactsAccess = .full

    func requestAccess() async -> ContactsAccess { access }

    func cards() async -> [CardChoice] {
        [
            CardChoice(id: "preview-card", name: "Alex Rivera", detail: "alex.rivera@example.com"),
            CardChoice(id: "casey", name: "Casey Morgan", detail: "casey@example.net")
        ]
    }

    func link(_ identifier: String) async throws(CardWriteFailure) -> CardLink {
        PreviewData.link()
    }
}

extension AppModel {
    static func preview(linked: Bool = true, finished: Bool = true, access: ContactsAccess = .full) -> AppModel {
        let defaults = UserDefaults(suiteName: "preview") ?? .standard
        defaults.set(finished, forKey: finishedOnboardingKey)
        let state = AppState(values: PreviewData.emails + PreviewData.phones + PreviewData.addresses,
                             cardLink: linked ? PreviewData.link() : nil)
        return AppModel(
            store: InMemoryStore(state: state, events: PreviewData.events), gateway: PreviewGateway(),
            contacts: PreviewContacts(access: access), defaults: defaults
        )
    }
}

extension View {
    func previewModel(_ model: AppModel = .preview()) -> some View {
        environment(model).task { await model.reload() }
    }
}
