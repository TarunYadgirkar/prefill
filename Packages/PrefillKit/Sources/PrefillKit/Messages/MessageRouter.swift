import Foundation
import os
import Synchronization

// Answers the Safari extension. Runs inside the extension's handler process, which
// inherits the app's Contacts grant; nothing here ever asks for access (REPORT.md,
// Spike results). The app writes AppState, this process only appends ExtensionEvents.
public struct MessageRouter: Sendable {
    static let log = PrefillLog.logger("messages")

    let store: any SharedStore
    let gateway: any ContactsGateway
    let now: @Sendable () -> Date

    public init(store: any SharedStore, gateway: any ContactsGateway, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.gateway = gateway
        self.now = now
    }

    public func route(_ message: Any?) -> ExtensionResponse {
        let request: ExtensionRequest
        do {
            request = try MessageCoding.request(from: message)
        } catch {
            Self.log.error("unreadable message: \(MessageCoding.failureName(error), privacy: .public)")
            return .error(reason: "unknown message")
        }
        switch request {
        case .ping: return .pong
        case .pageContext(let body): return .pageContext(pageContext(body))
        case .capture(let body): return .capture(capture(body))
        case .linkSuggestions(let body): return .linkSuggestions(linkSuggestions(body))
        case .contactSuggestions(let body): return .contactSuggestions(contactSuggestions(body))
        case .customSuggestions(let body): return .customSuggestions(customSuggestions(body))
        default: return other(request)
        }
    }

    private func other(_ request: ExtensionRequest) -> ExtensionResponse {
        if case .answers(let body) = request { return .answers(answers(body)) }
        return .popupState(sheet(request))
    }

    // Every rewrite syncs the card to all of the person's devices, so pages together get a
    // few rewrites a minute. Past that the card keeps its order until the next minute.
    static let maxCardWritesPerWindow = 6
    static let cardWriteWindow: TimeInterval = 60

    static let pageSeenInterval: TimeInterval = 86_400

    // Safari can deliver a capture and a page context to the same handler process at once,
    // and the Mac relay answers connections in parallel. Both read their limits from the
    // events before appending to them, so they run one at a time.
    static let eventLock = Mutex(())

    func pageContext(_ request: PageContextRequest) -> PageContextResponse {
        Self.eventLock.withLock { _ in
            notePageSeen(at: now())
            guard let state = currentState() else { return PageContextResponse(outcome: .failed(.other)) }
            guard let link = state.cardLink else { return PageContextResponse(status: .notSetUp) }
            guard state.settings.matchEachSite else { return PageContextResponse(status: .off) }
            let date = now()
            let recent = events().cardWrites.count { date.timeIntervalSince($0) < Self.cardWriteWindow }
            guard recent < Self.maxCardWritesPerWindow else {
                Self.log.info("card rewrite skipped, too many this minute")
                return PageContextResponse(status: .unchanged)
            }
            let page = PageSignal(
                host: request.host, hints: request.hints, now: date, matchEachSite: true,
                siteKinds: state.siteKinds, focusLabel: state.settings.focusLabel
            )
            let result = CardWriter(gateway: gateway).sync(syncRequest(state, link: link, page: page))
            if result.outcome == .saved { noteCardWrite(at: date) }
            return PageContextResponse(outcome: result.outcome)
        }
    }

    func notePageSeen(at date: Date) {
        if let seen = events().lastPageSeen, date.timeIntervalSince(seen) < Self.pageSeenInterval { return }
        append(ExtensionEvents(lastPageSeen: date))
    }

    func noteCardWrite(at date: Date) {
        append(ExtensionEvents(cardWrites: [date]))
    }

    @discardableResult
    func append(_ new: ExtensionEvents) -> Bool {
        do {
            try store.appendEvents(new)
            return true
        } catch {
            Self.log.error("events not saved: \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
    }

    // AppState with the choices made in Safari's Prefill sheet that the app hasn't folded in yet.
    func currentState() -> AppState? {
        appState()?.folding(events())
    }

    func appState() -> AppState? {
        do {
            return try store.readAppState()
        } catch {
            Self.log.error("app state unreadable: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    // Events are expendable history: a damaged item reads as empty rather than blocking.
    func events() -> ExtensionEvents {
        (try? store.readEvents()) ?? ExtensionEvents()
    }

    func syncRequest(
        _ state: AppState, link: CardLink, page: PageSignal,
        additions: [ContactValue] = [], newUsage: [UsageEvent] = []
    ) -> CardSyncRequest {
        CardSyncRequest(
            cardIdentifier: link.contactIdentifier, known: state.values, additions: additions,
            usage: events().usage + newUsage, pins: state.pins, page: page
        )
    }
}
