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
    // What is on the person's own card, which Share Contact sends, and what Prefill's contact holds.
    private(set) var placement = CardPlacement(onCard: [])
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

    // The one model of the running app, shared by its screens and its intents.
    static let shared = live()

    static func live() -> AppModel {
        let gateway = CNContactStoreGateway()
        let store = StoreFactory.make()
        ReinstallCleanup.run(store: store, defaults: .standard)
        return AppModel(store: store, gateway: gateway, contacts: LiveContactsSource(gateway: gateway))
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

    // Answers Prefill saved from job applications that are still as saved, newest first.
    var learnedAnswers: [LearnedAnswer] {
        events.answers.reversed().filter { answer in customFields.contains { answer.matches($0) } }
    }

    var waitingCount: Int {
        recent.count { $0.state == .waiting }
    }

    // Safari can't report the All Websites switch, but the extension only reports forms
    // once it is allowed to run on them.
    var isAllowedOnWebsites: Bool {
        events.lastPageSeen != nil || !events.usage.isEmpty || !events.captures.isEmpty
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

    // Siri, Shortcuts and Focus can run an intent before the app has drawn anything, and
    // the extension may have written since, so each intent reads the store and card first.
    func refreshForIntent() async {
        readStore()
        access = contacts.access
        await refreshCard()
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
            if let fresh = await CardWork.placement(gateway, identifier: link.contactIdentifier) {
                placement = fresh
            }
        case .failure(let failure):
            cardFailure = failure
        }
    }

    func refreshExtension() async {
        extensionEnabled = await SafariExtension.isEnabled()
        events = (try? store.readEvents()) ?? events
        foldSafariChoices()
    }

    func finishOnboarding() {
        hasFinishedOnboarding = true
        defaults.set(true, forKey: Self.finishedOnboardingKey)
    }

    // Forgets everything Prefill stored and starts setup again. The contact card is left as it is.
    func deleteAllData() async {
        do {
            try store.removeAll()
        } catch {
            problem = Problem(
                title: String(localized: "Prefill couldn’t delete its data"),
                message: String(localized: "Nothing was deleted. Try again in a moment.")
            )
            return
        }
        defaults.removeObject(forKey: Self.finishedOnboardingKey)
        hasFinishedOnboarding = false
        state = AppState()
        events = ExtensionEvents()
        await reload()
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

    func readStore() {
        state = (try? store.readAppState()) ?? state
        events = (try? store.readEvents()) ?? events
        foldSafariChoices()
    }

    // Pins, "Don't save on this site" and undone saves from Safari's Prefill sheet.
    private func foldSafariChoices() {
        let folded = state.folding(events)
        guard folded != state else { return }
        commit(folded)
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

    // Nil when the card couldn't be read, so the screen doesn't claim it is clean.
    @concurrent static func placement(_ gateway: any ContactsGateway, identifier: String) async -> CardPlacement? {
        try? gateway.placement(identifier: identifier)
    }

    @concurrent static func moveOffCard(
        _ gateway: any ContactsGateway, _ chosen: [CardExtra], identifier: String
    ) async -> CardWriteFailure? {
        do throws(CardWriteFailure) {
            try gateway.moveOffCard(chosen, identifier: identifier)
            return nil
        } catch {
            return error
        }
    }

    @concurrent static func moveOntoCard(
        _ gateway: any ContactsGateway, _ chosen: [CardExtra]?, identifier: String, leavingMinimal: Bool
    ) async -> CardWriteFailure? {
        do throws(CardWriteFailure) {
            try gateway.moveOntoCard(chosen, identifier: identifier, leavingMinimal: leavingMinimal)
            return nil
        } catch {
            return error
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
