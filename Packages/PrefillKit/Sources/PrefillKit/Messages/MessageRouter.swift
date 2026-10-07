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
        case .capture(let body): return .capture(capture(body))
        case .linkSuggestions(let body): return .linkSuggestions(linkSuggestions(body))
        case .contactSuggestions(let body): return .contactSuggestions(contactSuggestions(body))
        case .customSuggestions(let body): return .customSuggestions(customSuggestions(body))
        default: return other(request)
        }
    }

    private func other(_ request: ExtensionRequest) -> ExtensionResponse {
        if case .answers(let body) = request { return .answers(answers(body)) }
        if case .picked(let body) = request { return .picked(picked(body)) }
        return .popupState(sheet(request))
    }

    static let pageSeenInterval: TimeInterval = 86_400

    // Safari can deliver a capture and a pick to the same handler process at once, and the
    // Mac relay answers connections in parallel. Both read their limits from the events
    // before appending to them, so they run one at a time.
    static let eventLock = Mutex(())

    // A page with contact fields asks for suggestions, which shows the app the extension
    // is allowed to run on websites.
    func notePageSeen() {
        Self.eventLock.withLock { _ in
            let date = now()
            if let seen = events().lastPageSeen, date.timeIntervalSince(seen) < Self.pageSeenInterval { return }
            append(ExtensionEvents(lastPageSeen: date))
        }
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
