import Foundation
import os

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
        }
    }

    func pageContext(_ request: PageContextRequest) -> PageContextResponse {
        let state: AppState
        do {
            state = try store.readAppState()
        } catch {
            Self.log.error("app state unreadable: \(String(describing: type(of: error)), privacy: .public)")
            return PageContextResponse(outcome: .failed(.other))
        }
        guard let link = state.cardLink else { return PageContextResponse(status: .notSetUp) }
        guard state.settings.matchEachSite else { return PageContextResponse(status: .off) }
        let page = PageSignal(host: request.host, hints: request.hints, now: now(), matchEachSite: true)
        let result = CardWriter(gateway: gateway).sync(syncRequest(state, link: link, page: page))
        return PageContextResponse(outcome: result.outcome)
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
