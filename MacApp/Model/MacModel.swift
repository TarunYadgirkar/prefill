import Contacts
import Foundation
import Observation
import PrefillKit
import ServiceManagement

// What the menu and the settings window show: Contacts access, the person's own card, the
// browsers Prefill is set up in, and values waiting for review. The app writes AppState;
// the relay, which answers the browsers, only appends events, as the Safari extension does
// on iPhone.
@MainActor
@Observable
final class MacModel {
    enum Access: Equatable {
        case notDetermined, granted, denied
    }

    static let shared = MacModel()
    private static let loginItemKey = "registeredLoginItem"
    private static let heardFromExtensionKey = "heardFromExtension"
    private static let skippedExtensionKey = "skippedExtension"

    private(set) var access = Access.notDetermined
    private(set) var card: CardRecord?
    // What is on My Card, which sharing the card sends along, and what Prefill's contact holds.
    private(set) var placement = CardPlacement(onCard: [])
    private(set) var hasMeCard = true
    private(set) var state = AppState()
    private(set) var events = ExtensionEvents()
    private(set) var browsers: [BrowserHost] = []
    private(set) var isRelayRunning = false
    private(set) var opensAtLogin = false
    private(set) var isAccessibilityTrusted = AccessibilityTrust.isTrusted
    // Set once Prefill's host has relayed a request, which only the browser extension starts.
    private(set) var hasHeardFromExtension = UserDefaults.standard.bool(forKey: heardFromExtensionKey)
    private(set) var skippedExtension = UserDefaults.standard.bool(forKey: skippedExtensionKey)
    var problem: String?

    let store: any SharedStore
    let gateway: any ContactsGateway
    // Set only in the browser test build, which uses a fixed card instead of My Card.
    private let fixedLink: CardLink?
    @ObservationIgnored private var server: RelayServer?
    @ObservationIgnored private var cardObserver: (any NSObjectProtocol)?

    init() {
        #if PREFILL_TEST_BROWSERS
        if let fixture = E2EFixture.gateway, let store = E2EFixture.store {
            self.store = store
            self.gateway = fixture
            self.fixedLink = fixture.link
            return
        }
        #endif
        self.store = AppGroupStore(directory: RelaySocket.directory.appending(path: "Store"))
        self.gateway = CNContactStoreGateway()
        self.fixedLink = nil
    }

    var cardName: String {
        guard let card else { return "" }
        return [card.givenName, card.familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var waiting: [RecentItem] {
        guard let card else { return [] }
        return RecentCaptures.items(events: events, state: state, card: card).filter { $0.state == .waiting }
    }

    func values(_ kind: ContactKind) -> [ContactValue] {
        guard let card else { return [] }
        return ManualOrder.values(kind, card: card, known: state.values, now: .now)
    }

    func start() async {
        guard server == nil else { return }
        let router = MessageRouter(store: store, gateway: gateway)
        server = RelayServer(router: router) {
            Task { @MainActor in MacModel.shared.relayAnswered() }
        }
        isRelayRunning = server != nil
        cardObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await MacModel.shared.refresh() }
        }
        if fixedLink == nil { registerLoginItemOnce() }
        await refresh()
    }

    func refresh() async {
        readStore()
        access = fixedLink == nil ? Self.currentAccess : .granted
        browsers = fixedLink == nil ? HostInstaller.installAll() : []
        opensAtLogin = SMAppService.mainApp.status == .enabled
        isAccessibilityTrusted = AccessibilityTrust.isTrusted
        guard access == .granted else {
            card = nil
            return
        }
        await linkMeCard()
        await refreshCard()
    }

    // Contacts and Accessibility are granted in System Settings, which tells Prefill nothing,
    // so the setup list asks again while it's on screen.
    func recheckSetup() async {
        isAccessibilityTrusted = AccessibilityTrust.isTrusted
        guard fixedLink == nil, Self.currentAccess != access else { return }
        await refresh()
    }

    func skipExtension() {
        skippedExtension = true
        UserDefaults.standard.set(true, forKey: Self.skippedExtensionKey)
    }

    private func relayAnswered() {
        readStore()
        guard !hasHeardFromExtension else { return }
        hasHeardFromExtension = true
        UserDefaults.standard.set(true, forKey: Self.heardFromExtensionKey)
    }

    func requestAccess() async {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        await refresh()
    }

    func readStore() {
        state = (try? store.readAppState()) ?? state
        events = (try? store.readEvents()) ?? events
        let folded = state.folding(events)
        if folded != state { commit(folded) }
    }

    func commit(_ next: AppState) {
        state = next
        do {
            try store.writeAppState(next)
        } catch {
            problem = String(localized: "Prefill couldn’t save that. Try it again in a moment.")
        }
    }

    private static var currentAccess: Access {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    // Follows the card set as My Card, which can change in Contacts at any time.
    private func linkMeCard() async {
        if let fixedLink {
            guard state.cardLink?.contactIdentifier != fixedLink.contactIdentifier else { return }
            commit(state.with(cardLink: fixedLink))
            return
        }
        let gateway = gateway
        let result = await Task.detached { () -> Result<CardLink, MeCard.Failure> in
            do throws(MeCard.Failure) {
                return .success(try MeCard.link(gateway: gateway, now: .now))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let link):
            hasMeCard = true
            guard link.contactIdentifier != state.cardLink?.contactIdentifier else { return }
            commit(state.with(cardLink: link))
        case .failure:
            hasMeCard = false
        }
    }

    private func refreshCard() async {
        guard let identifier = state.cardLink?.contactIdentifier else {
            card = nil
            return
        }
        let gateway = gateway
        let (result, fresh) = await Task.detached {
            (Result { () throws(CardWriteFailure) in try gateway.fetchCard(identifier: identifier) },
             try? gateway.placement(identifier: identifier))
        }.value
        if let fresh { placement = fresh }
        let fetched: CardRecord
        switch result {
        case .success(let record):
            fetched = record
        case .failure(.cardMissing):
            card = nil
            return
        case .failure:
            // Keep the last card on screen: a passing Contacts error isn't an empty card.
            problem = String(localized: "Prefill couldn’t read your card. Try it again in a moment.")
            return
        }
        card = fetched
        let merged = ManualOrder.allValues(card: fetched, known: state.values, now: .now)
        if merged.map(\.id) != state.values.map(\.id) { commit(state.with(values: merged)) }
    }

    func setOpensAtLogin(_ isOn: Bool) {
        do {
            if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = String(localized: "Prefill couldn’t change that. Check Login Items in System Settings.")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func registerLoginItemOnce() {
        guard !UserDefaults.standard.bool(forKey: Self.loginItemKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.loginItemKey)
        try? SMAppService.mainApp.register()
    }
}
