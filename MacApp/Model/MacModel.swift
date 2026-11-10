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
    static let heardFromExtensionKey = "heardFromExtension"
    private static let skippedExtensionKey = "skippedExtension"
    private static let heardBrowsersKey = "heardBrowsers"
    static let seenWelcomeKey = "seenWelcome"

    private(set) var access = Access.notDetermined
    private(set) var card: CardRecord? { didSet { refreshOffers() } }
    // What is on My Card, which sharing the card sends along, and what Prefill's contact holds.
    private(set) var placement = CardPlacement(onCard: [])
    private(set) var hasMeCard = true
    private(set) var state = AppState() { didSet { refreshOffers() } }
    private(set) var events = ExtensionEvents()
    private(set) var browsers: [BrowserHost] = []
    private(set) var isRelayRunning = false
    private(set) var opensAtLogin = false
    private(set) var isAccessibilityTrusted = AccessibilityTrust.isTrusted
    // Set once Prefill's host has relayed a request, which only the browser extension starts.
    private(set) var hasHeardFromExtension = UserDefaults.standard.bool(forKey: heardFromExtensionKey)
    private(set) var skippedExtension = UserDefaults.standard.bool(forKey: skippedExtensionKey)
    // The browsers whose Prefill extension has talked to the app, by bundle identifier. Without
    // the extension a browser gets only the Accessibility panel, which saves and records nothing.
    private(set) var heardBrowsers = Set(UserDefaults.standard.stringArray(forKey: heardBrowsersKey) ?? [])
    private(set) var isSafariExtensionOn = false
    private(set) var hasSeenWelcome = UserDefaults.standard.bool(forKey: seenWelcomeKey)
    var problem: String?
    @ObservationIgnored private var isStateUnreadable = false
    // Job applications sent from the browsers here, and from the iPhone once its history is
    // copied over USB (scripts/sync-applications.sh), newest first.
    var applications: [SubmittedApplication] = [] { didSet { refreshOffers() } }
    // Read from the applications, the card and the state when one changes, never while drawing.
    var answerOffers: [AnswerOffer] = []
    // Where applications go in the person's Google Sheet, once they add its link (MacModel+Sheet).
    var sheet = SheetSettingsFile(directory: RelaySocket.directory).read()
    var sheetProblem: String?
    var sheetNeedsSignIn = false

    let store: any SharedStore
    let gateway: any ContactsGateway
    // Set only in the browser test build, which uses a fixed card instead of My Card.
    private let fixedLink: CardLink?
    @ObservationIgnored let archive = ApplicationArchive(directory: RelaySocket.directory)
    @ObservationIgnored let sheetFile = SheetSettingsFile(directory: RelaySocket.directory)
    @ObservationIgnored let google = GoogleAccount()
    @ObservationIgnored var isSendingToSheet = false
    @ObservationIgnored private var server: RelayServer?
    @ObservationIgnored private var safariServer: RelayServer?
    @ObservationIgnored private var cardObserver: (any NSObjectProtocol)?
    // Set in the build the paid team signs (MacModel+Cloud).
    @ObservationIgnored var cloud: PrefillCloud?

    init() {
        #if PREFILL_TEST_BROWSERS
        if let fixture = E2EFixture.gateway, let store = E2EFixture.store {
            self.store = store
            self.gateway = fixture
            self.fixedLink = fixture.link
            if E2EFixture.isShowcase {
                hasHeardFromExtension = true
                E2EFixture.seedShowcase(store)
            }
            return
        }
        #endif
        self.store = AppGroupStore(directory: RelaySocket.directory.appending(path: "Store"))
        self.gateway = Self.liveGateway()
        self.fixedLink = nil
    }

    // The screenshot run: a finished setup on the fixture card, with nothing asked of macOS.
    static var isShowcase: Bool {
        #if PREFILL_TEST_BROWSERS
        E2EFixture.isShowcase
        #else
        false
        #endif
    }

    var cardName: String {
        guard let card else { return "" }
        return [card.givenName, card.familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var waiting: [RecentItem] {
        guard let card else { return [] }
        return RecentCaptures.items(events: events, state: state, card: card).filter { $0.state == .waiting }
    }

    func start() async {
        guard server == nil else { return }
        let router = MessageRouter(store: store, gateway: gateway)
        let answered: @Sendable () -> Void = { Task { @MainActor in MacModel.shared.relayAnswered() } }
        server = RelayServer(
            path: RelaySocket.path, peer: CodeIdentity.hostIdentifier, router: router, answered: answered
        )
        safariServer = RelaySocket.safariPath.flatMap {
            RelayServer(path: $0, peer: CodeIdentity.safariIdentifier, router: router, answered: answered)
        }
        isRelayRunning = server != nil
        cardObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await MacModel.shared.refresh() }
        }
        if fixedLink == nil {
            registerLoginItemOnce()
            startCloud()
        }
        await refresh()
    }

    func refresh() async {
        readStore()
        Task { await cloud?.fetch() }
        access = fixedLink == nil ? Self.currentAccess : .granted
        browsers = fixedLink == nil ? HostInstaller.installAll() : []
        opensAtLogin = SMAppService.mainApp.status == .enabled
        isAccessibilityTrusted = AccessibilityTrust.isTrusted || Self.isShowcase
        isSafariExtensionOn = await SafariExtension.isOn()
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
        isAccessibilityTrusted = AccessibilityTrust.isTrusted || Self.isShowcase
        isSafariExtensionOn = await SafariExtension.isOn()
        guard fixedLink == nil, Self.currentAccess != access else { return }
        await refresh()
    }

    private func relayAnswered() {
        readStore()
        noteHeardBrowsers()
        guard !hasHeardFromExtension else { return }
        hasHeardFromExtension = true
        UserDefaults.standard.set(true, forKey: Self.heardFromExtensionKey)
    }

    func requestAccess() async {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        await refresh()
    }

    // Forgets everything Prefill stored on this Mac: the store, the applications and those
    // waiting to merge in from the iPhone. The contact card is left as it is.
    func deleteAllData() async {
        guard await deleteCloudCopy() else { return }
        guard deleteFiles() else {
            problem = String(localized: "Some of Prefill’s data is still on this Mac. Delete again in a moment.")
            readStore()
            return
        }
        for key in [Self.heardFromExtensionKey, Self.skippedExtensionKey, Self.heardBrowsersKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        heardBrowsers = []
        hasHeardFromExtension = false
        skippedExtension = false
        state = AppState()
        events = ExtensionEvents()
        applications = []
        sheet = SheetSettings()
        sheetProblem = nil
        sheetNeedsSignIn = false
        await refresh()
    }

    func readStore() {
        // A state that can't be read is never taken for an empty one: commit won't replace it.
        let stored = try? store.readAppState()
        isStateUnreadable = stored == nil
        state = stored ?? state
        events = (try? store.readEvents()) ?? events
        let folded = state.folding(events)
        if folded != state { commit(folded) }
        archiveApplications()
    }

    func setApplications(_ merged: [SubmittedApplication]) {
        cloud?.sendApplications(ApplicationArchive.changed(from: applications, to: merged))
        applications = merged
        Task { await askAboutOffers() }
        Task { await sendToSheet() }
    }

    func commit(_ next: AppState) {
        state = next
        guard !isStateUnreadable else {
            problem = String(localized: "Prefill couldn’t read what it saved earlier. Quit Prefill and open it again.")
            return
        }
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

extension MacModel {
    func values(_ kind: ContactKind) -> [ContactValue] {
        guard let card else { return [] }
        return ManualOrder.values(kind, card: card, known: state.values, now: .now)
    }

    func skipExtension() {
        skippedExtension = true
        UserDefaults.standard.set(true, forKey: Self.skippedExtensionKey)
    }

    func finishWelcome() {
        hasSeenWelcome = true
        UserDefaults.standard.set(true, forKey: Self.seenWelcomeKey)
    }

    private func noteHeardBrowsers() {
        let heard = heardBrowsers.union(ExtensionPresence.seen)
        guard heard != heardBrowsers else { return }
        heardBrowsers = heard
        UserDefaults.standard.set(heard.sorted(), forKey: Self.heardBrowsersKey)
    }
}
