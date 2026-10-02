import Contacts
import Foundation
import Observation
import PrefillKit

// What the app knows and shows: the person's card as Contacts has it, the order they want,
// and what the Safari extension has reported. Values never leave the device and are never
// logged; only the card and the shared store hold them.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading, onboarding, ready
    }

    struct Problem: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    static let finishedOnboardingKey = "finishedOnboarding"

    private(set) var state = AppState()
    private(set) var events = ExtensionEvents()
    private(set) var card: CardRecord?
    private(set) var cardFailure: CardWriteFailure?
    private(set) var access: ContactsAccess
    private(set) var extensionEnabled: Bool?
    private(set) var hasFinishedOnboarding: Bool
    private(set) var isLoaded = false
    private(set) var intelligenceState = IntelligenceState.unsupported
    var problem: Problem?

    let store: any SharedStore
    let gateway: any ContactsGateway
    let contacts: any ContactsSource
    private let defaults: UserDefaults
    @ObservationIgnored let intelligence = Intelligence()
    @ObservationIgnored var isAskingModel = false
    @ObservationIgnored private var cardObserver: (any NSObjectProtocol)?

    init(
        store: any SharedStore, gateway: any ContactsGateway, contacts: any ContactsSource,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.gateway = gateway
        self.contacts = contacts
        self.defaults = defaults
        self.access = contacts.access
        self.hasFinishedOnboarding = defaults.bool(forKey: Self.finishedOnboardingKey)
    }

    static func live() -> AppModel {
        let gateway = CNContactStoreGateway()
        return AppModel(store: StoreFactory.make(), gateway: gateway, contacts: LiveContactsSource(gateway: gateway))
    }

    var phase: Phase {
        guard isLoaded else { return .loading }
        return state.cardLink == nil || !hasFinishedOnboarding ? .onboarding : .ready
    }

    var cardName: String {
        guard let card else { return "" }
        return [card.givenName, card.familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func values(_ kind: ContactKind) -> [ContactValue] {
        guard let card else { return [] }
        return ManualOrder.values(kind, card: card, known: state.values, now: .now)
    }

    var sites: [SiteSummary] {
        guard let card else { return [] }
        return SiteDirectory.sites(state: state, events: events, card: card, now: .now)
    }

    func site(_ host: String) -> SiteSummary? {
        sites.first { $0.host == host }
    }

    var recent: [RecentItem] {
        guard let card else { return [] }
        return RecentCaptures.items(events: events, state: state, card: card)
    }

    var waitingCount: Int {
        recent.count { $0.state == .waiting }
    }

    // Safari can't report the All Websites switch, but the extension only reports forms
    // once it is allowed to run on them.
    var isAllowedOnWebsites: Bool {
        !events.usage.isEmpty || !events.captures.isEmpty
    }

    func start() async {
        cardObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshCard() }
        }
        await reload()
    }

    func reload() async {
        readStore()
        access = contacts.access
        await refreshCard()
        await refreshExtension()
        isLoaded = true
        intelligenceState = Intelligence.state
        await refreshInsights()
    }

    func refreshCard() async {
        guard let link = state.cardLink, access.isGranted else {
            card = nil
            cardFailure = state.cardLink == nil ? nil : .noAccess
            return
        }
        switch await CardWork.fetch(gateway, identifier: link.contactIdentifier) {
        case .success(let fresh):
            card = fresh
            cardFailure = nil
            adoptCardValues(fresh)
        case .failure(let failure):
            cardFailure = failure
        }
    }

    func refreshExtension() async {
        extensionEnabled = await SafariExtension.isEnabled()
        events = (try? store.readEvents()) ?? events
    }

    func finishOnboarding() {
        hasFinishedOnboarding = true
        defaults.set(true, forKey: Self.finishedOnboardingKey)
    }

    func requestAccess() async {
        access = await contacts.requestAccess()
    }

    // Writes AppState, the one document the app owns.
    func commit(_ next: AppState) {
        state = next
        do {
            try store.writeAppState(next)
        } catch {
            problem = Problem(
                title: String(localized: "Prefill couldn’t save that"),
                message: String(localized: "Your change shows here but wasn’t stored. Try it again in a moment.")
            )
        }
    }

    func report(_ failure: CardWriteFailure) {
        problem = Problem(title: String(localized: "Your card didn’t change"), message: failure.appMessage)
    }

    private func readStore() {
        state = (try? store.readAppState()) ?? state
        events = (try? store.readEvents()) ?? events
    }

    // Values added to the card elsewhere join the person's order where the card has them.
    private func adoptCardValues(_ card: CardRecord) {
        let merged = ManualOrder.allValues(card: card, known: state.values, now: .now)
        guard merged.map(\.id) != state.values.map(\.id) else { return }
        commit(state.with(values: merged))
    }
}

extension CardWriteFailure {
    // The extension's reasons send people to the app; here they're already in it.
    var appMessage: String {
        switch self {
        case .noAccess: String(localized: """
            Prefill can’t reach your contact card. Turn on Contacts access for Prefill in Settings.
            """)
        case .cardMissing: String(localized: """
            Prefill can’t find your contact card. Choose your card again in Prefill’s settings.
            """)
        case .notWritable, .changedDuringSave, .other: reason
        }
    }
}

// Contacts calls block, so they run off the main actor.
nonisolated enum CardWork {
    @concurrent static func fetch(
        _ gateway: any ContactsGateway, identifier: String
    ) async -> Result<CardRecord, CardWriteFailure> {
        do throws(CardWriteFailure) {
            return .success(try gateway.fetchCard(identifier: identifier))
        } catch {
            return .failure(error)
        }
    }

    @concurrent static func sync(_ gateway: any ContactsGateway, _ request: CardSyncRequest) async -> CardWriteOutcome {
        CardWriter(gateway: gateway).sync(request).outcome
    }

    @concurrent static func edit(
        _ gateway: any ContactsGateway, _ edit: CardEditor.Edit, identifier: String
    ) async -> CardWriteOutcome {
        CardEditor(gateway: gateway).apply(edit, cardIdentifier: identifier)
    }
}
