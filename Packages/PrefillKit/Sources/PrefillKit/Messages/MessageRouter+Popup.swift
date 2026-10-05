import Foundation

// Safari's Prefill sheet: what Safari will offer on this site, picking a value there, the
// values saved from the site with Undo, and "Don't save on this site". Every answer is the
// sheet's state for the site, so the sheet redraws from the reply.
extension MessageRouter {
    func sheet(_ request: ExtensionRequest) -> PopupStateResponse {
        switch request {
        case .popupState(let body): popupState(host: body.host, kinds: body.kinds)
        case .pin(let body): choose(body.valueID, kind: body.kind, host: body.host)
        case .unpin(let body): choose(nil, kind: body.kind, host: body.host)
        case .undoCapture(let body): undoCapture(body)
        case .muteSite(let body): muteSite(body)
        case .ping, .pageContext, .capture, .linkSuggestions, .contactSuggestions, .customSuggestions, .answers:
            PopupStateResponse(failure: .other)
        }
    }

    // Reads the card and plans this site's order without saving it.
    func popupState(host: String, kinds: [ContactKind]) -> PopupStateResponse {
        guard let stored = appState() else { return PopupStateResponse(failure: .other) }
        guard let link = stored.cardLink else { return PopupStateResponse(status: .notSetUp) }
        let events = events()
        let state = stored.folding(events)
        let card: CardRecord
        do {
            card = try gateway.fetchCard(identifier: link.contactIdentifier)
        } catch {
            return PopupStateResponse(failure: error)
        }
        let isSiteSpecific = state.settings.matchEachSite
        let page = PageSignal(
            host: host, hints: [:], now: now(), matchEachSite: isSiteSpecific,
            siteKinds: state.siteKinds, focusLabel: state.settings.focusLabel
        )
        let target = CardPlan(card: card, request: syncRequest(state, link: link, page: page)).target
        let site = Normalizer.registrableDomain(host)
        let shown = kinds.reduce(into: [ContactKind]()) { if $1 != .link, !$0.contains($1) { $0.append($1) } }
        return PopupStateResponse(
            status: isSiteSpecific ? .ready : .off,
            kinds: shown.map { kind in
                let values = target.entries(kind).map { ContactValue(entry: $0, createdAt: page.now) }.uniqued()
                return PopupKind(
                    kind: kind, values: values.prefix(MessageLimits.popupValues).map(PopupValue.init),
                    pinnedID: isSiteSpecific ? state.pinnedValue(kind, on: site) : nil
                )
            },
            recent: RecentCaptures.items(events: events, state: state, card: card)
                .filter { $0.host == site && $0.value.kind != .link }
                .prefix(MessageLimits.popupRecent)
                .map(PopupRecent.init),
            muted: state.isMuted(site)
        )
    }

    // Pins the value for the site, or with a nil value unpins it, and puts the card in this
    // site's order right away so the next tap in a field shows it.
    func choose(_ valueID: UUID?, kind: ContactKind, host: String) -> PopupStateResponse {
        guard let stored = appState() else { return PopupStateResponse(failure: .other) }
        guard let link = stored.cardLink else { return PopupStateResponse(status: .notSetUp) }
        guard stored.settings.matchEachSite else { return popupState(host: host, kinds: [kind]) }
        let date = now()
        let site = Normalizer.registrableDomain(host)
        guard append(ExtensionEvents(pins: [PinEvent(host: site, kind: kind, valueID: valueID, date: date)])) else {
            return PopupStateResponse(failure: .other)
        }
        guard let state = currentState() else { return PopupStateResponse(failure: .other) }
        let page = PageSignal(
            host: host, hints: [:], now: date, matchEachSite: true,
            siteKinds: state.siteKinds, focusLabel: state.settings.focusLabel
        )
        let outcome = CardWriter(gateway: gateway).sync(syncRequest(state, link: link, page: page)).outcome
        if case .failed(let failure) = outcome { return PopupStateResponse(failure: failure) }
        if outcome == .saved { noteCardWrite(at: date) }
        return popupState(host: host, kinds: [kind])
    }

    // Takes a value saved from this site off the card, or turns down one waiting for review.
    // Only values Prefill captured qualify, so nothing the person put on the card is removed.
    // A value already undone or turned down is on the card again only because the person
    // put it back by hand, so it stays.
    func undoCapture(_ request: UndoCaptureRequest) -> PopupStateResponse {
        guard let state = currentState() else { return PopupStateResponse(failure: .other) }
        guard let link = state.cardLink else { return PopupStateResponse(status: .notSetUp) }
        let site = Normalizer.registrableDomain(request.host)
        let capture = events().captures.last {
            $0.host == site && $0.value.id == request.valueID && $0.value.source == .captured
                && ($0.verdict == .saved || $0.verdict == .needsReview)
        }
        guard let capture, !state.rejectedValueIDs.contains(capture.value.id) else {
            return popupState(host: request.host, kinds: [])
        }
        if capture.verdict == .saved {
            let editor = CardEditor(gateway: gateway)
            let outcome = editor.apply(.remove(capture.value), cardIdentifier: link.contactIdentifier)
            if case .failed(let failure) = outcome { return PopupStateResponse(failure: failure) }
        }
        let dismissed = Capture(host: site, value: capture.value, date: now(), verdict: .dismissed)
        guard append(ExtensionEvents(captures: [dismissed])) else { return PopupStateResponse(failure: .other) }
        return popupState(host: request.host, kinds: [capture.kind])
    }

    func muteSite(_ request: MuteSiteRequest) -> PopupStateResponse {
        let site = Normalizer.registrableDomain(request.host)
        guard append(ExtensionEvents(mutes: [MuteEvent(host: site, isMuted: request.muted, date: now())])) else {
            return PopupStateResponse(failure: .other)
        }
        return popupState(host: request.host, kinds: [])
    }
}
