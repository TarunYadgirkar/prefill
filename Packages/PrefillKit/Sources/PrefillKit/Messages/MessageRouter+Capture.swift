import Foundation
import os

extension MessageRouter {
    // Without a linked card there is nothing to compare against and nobody has agreed to
    // anything yet, so a capture is dropped whole.
    func capture(_ request: CaptureRequest) -> CaptureResponse {
        let dropped = CaptureResponse(saved: 0, review: 0, ignored: request.fields.count)
        guard let state = try? store.readAppState(), let link = state.cardLink else { return dropped }
        let card: CardRecord
        do {
            card = try gateway.fetchCard(identifier: link.contactIdentifier)
        } catch {
            Self.log.error("capture skipped, card unreadable: \(String(describing: error), privacy: .public)")
            return dropped
        }
        let date = now()
        let filter = CaptureFilter(card: card, settings: state.settings, rejected: Set(state.rejectedValueIDs))
        let evaluated = filter.evaluate(request, at: date)
        let decisions = saveToCard(evaluated, request: request, state: state, link: link, at: date)
        record(decisions, host: request.host, at: date)
        return CaptureResponse(decisions: decisions)
    }

    // New values go onto the card ranked for this site, so the value just typed is the
    // one Safari offers here next time. If the card can't be saved they wait for review.
    private func saveToCard(
        _ decisions: [CaptureDecision], request: CaptureRequest, state: AppState, link: CardLink, at date: Date
    ) -> [CaptureDecision] {
        let additions = decisions.compactMap(\.savedValue)
        guard !additions.isEmpty else { return decisions }
        let page = PageSignal(
            host: request.host, hints: request.hints, now: date, matchEachSite: state.settings.matchEachSite
        )
        let usage = CaptureFilter.usage(from: decisions, host: request.host, at: date)
        let sync = syncRequest(state, link: link, page: page, additions: additions, newUsage: usage)
        guard case .failed = CardWriter(gateway: gateway).sync(sync).outcome else { return decisions }
        return decisions.map(\.reviewInsteadOfSave)
    }

    private func record(_ decisions: [CaptureDecision], host: String, at date: Date) {
        let usage = CaptureFilter.usage(from: decisions, host: host, at: date)
        let captures = CaptureFilter.captures(from: decisions, host: host, at: date)
        guard !usage.isEmpty || !captures.isEmpty else { return }
        do {
            try store.appendEvents(usage: usage, captures: captures)
        } catch {
            Self.log.error("events not saved: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}

private extension CaptureDecision {
    var savedValue: ContactValue? {
        if case .save(let value) = self { value } else { nil }
    }

    var reviewInsteadOfSave: CaptureDecision {
        if case .save(let value) = self { .review(value) } else { self }
    }
}
