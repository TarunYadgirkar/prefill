import AppIntents
import Contacts
import Foundation
import PrefillKit
import SwiftUI
@testable import Prefill
import Testing

// Runs the Siri, Shortcuts and Focus intents' perform() inside Prefill.app against the Alex
// Rivera card (testbed/alex-rivera.vcf), the way the system would call them. The intents
// get the app's model through AppDependencyManager when the system runs them; called
// directly, they need it set by hand, which `run` does.
// Only `scripts/test.sh intents` sets PREFILL_INTENTS. The test puts the card and the
// shared store back as it found them.
protocol ModelIntent {
    var model: AppModel { get set }
}

extension GetValueIntent: ModelIntent {}
extension BarPreviewSnippet: ModelIntent {}
extension PromoteValueIntent: ModelIntent {}
extension PreferInfoFocusFilter: ModelIntent {}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PREFILL_INTENTS"] != nil))
struct IntentsHostTests {
    private typealias ValueResult = IntentResultContainer<String, Never, _SnippetIntentContainer, IntentDialog>

    private let gateway = CNContactStoreGateway()
    private let store = StoreFactory.make()
    private let homeEmail = "alex.rivera@example.com"
    private let workEmail = "alex@work.example.org"
    private let schoolEmail = ContactValue(
        payload: .email("alex.school@example.edu"), label: nil, source: .card, createdAt: .now
    )

    @Test func intentsAnswerAndReorderTheAlexRiveraCard() async throws {
        let identifier = try alexIdentifier()
        let card = try gateway.fetchCard(identifier: identifier)
        let savedState = try? store.readAppState()
        let savedEvents = try? store.readEvents()
        do {
            try link(card)
            try await askAndReorder(identifier)
        } catch {
            try restore(card, state: savedState, events: savedEvents)
            throw error
        }
        try restore(card, state: savedState, events: savedEvents)
    }

    private func askAndReorder(_ identifier: String) async throws {
        let shipping = try await run(GetValueIntent(kind: .address, purpose: .shipping))
        #expect(value(shipping)?.hasPrefix("2400 Durant Ave") == true)

        _ = try await run(PreferInfoFocusFilter(preferred: .work))
        #expect(try store.readAppState().settings.focusLabel == "work")
        #expect(try firstEmail(identifier) == workEmail)
        #expect(value(try await run(GetValueIntent(kind: .email))) == workEmail)

        let netflix = SiteEntity(host: "www.netflix.com")
        _ = try await run(PromoteValueIntent(valueID: schoolEmail.id, kind: .email, site: netflix))
        let pin = SitePin(host: "netflix.com", kind: .email, valueID: schoolEmail.id)
        #expect(try store.readAppState().pins.contains(pin))
        #expect(try firstEmail(identifier) == schoolEmail.display)
        #expect(value(try await run(GetValueIntent(kind: .email, site: netflix))) == schoolEmail.display)
        _ = try await run(BarPreviewSnippet(kind: .email, site: netflix))
        try saveSnippetPicture(site: netflix)

        _ = try await run(PreferInfoFocusFilter(preferred: nil))
        #expect(try store.readAppState().settings.focusLabel == nil)
        #expect(try firstEmail(identifier) == homeEmail)
    }

    private func run<Intent: AppIntent & ModelIntent>(_ intent: Intent) async throws -> Intent.PerformResult {
        var intent = intent
        intent.model = AppModel.shared
        return try await intent.perform()
    }

    // The snippet as Siri would show it after the pin, for a look without a device. Only when
    // the script names a folder.
    private func saveSnippetPicture(site: SiteEntity) throws {
        guard let folder = ProcessInfo.processInfo.environment["PREFILL_SNAPSHOT_DIR"] else { return }
        let view = BarSnippetView(kind: .email, site: site, values: AppModel.shared.ranked(.email, host: site.id))
            .frame(width: 370)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let png = try #require(renderer.uiImage?.pngData())
        try png.write(to: URL(filePath: folder).appending(path: "intents-bar-snippet.png"))
    }

    private func value(_ result: some IntentResult) -> String? {
        (result as? ValueResult)?.value
    }

    private func firstEmail(_ identifier: String) throws -> String? {
        let keys = [CNContactEmailAddressesKey as CNKeyDescriptor]
        let contact = try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        return contact.emailAddresses.first.map { $0.value as String }
    }

    private func alexIdentifier() throws -> String {
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        let matches = try CNContactStore().unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: "Alex Rivera"), keysToFetch: keys
        )
        return try #require(matches.first?.identifier, "Alex Rivera is missing from this simulator")
    }

    private func link(_ card: CardRecord) throws {
        let values = [card.emails, card.phones, card.addresses].joined().map { entry in
            ContactValue(payload: entry.payload, label: entry.label, source: .card, createdAt: .now)
        }
        let link = CardLink(
            contactIdentifier: card.identifier, containerIdentifier: nil, linkedIdentifiers: [],
            original: card, snapshotAt: .now
        )
        try store.removeAll()
        try store.writeAppState(AppState(values: values, cardLink: link))
    }

    private func restore(_ card: CardRecord, state: AppState?, events: ExtensionEvents?) throws {
        let current = try gateway.fetchCard(identifier: card.identifier)
        _ = try gateway.save(card, basis: current, scope: .personEdit, transactionAuthor: CardWriter.transactionAuthor)
        try store.removeAll()
        if let state { try store.writeAppState(state) }
        if let events {
            try store.appendEvents(usage: events.usage, captures: events.captures, cardWrites: events.cardWrites)
        }
    }
}
