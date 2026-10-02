import Foundation
import os

extension MessageRouter {
    // A page can only put so much on the card: a few new values per form, and a few more
    // per hour across every site. The rest wait for review.
    static let maxSavesPerCapture = 3
    static let maxSavesPerWindow = 6
    static let saveWindow: TimeInterval = 3_600

    // Without a linked card there is nothing to compare against and nobody has agreed to
    // anything yet, and without the card nothing can be compared either, so in both cases
    // the capture is dropped whole (docs/messages.md, capture).
    func capture(_ request: CaptureRequest) -> CaptureResponse {
        let dropped = CaptureResponse(saved: 0, review: 0, ignored: request.fields.count)
        guard let state = appState(), let link = state.cardLink else { return dropped }
        let card: CardRecord
        do {
            card = try gateway.fetchCard(identifier: link.contactIdentifier)
        } catch {
            Self.log.error("capture skipped, card unreadable: \(String(describing: error), privacy: .public)")
            return dropped
        }
        let date = now()
        let filter = CaptureFilter(card: card, settings: state.settings, rejected: Set(state.rejectedValueIDs))
        let evaluated = limitingSaves(filter.evaluate(request, at: date), request: request, at: date)
        let context = CaptureContext(request: request, state: state, link: link, card: card, date: date)
        let decisions = saveToCard(evaluated, context: context)
        record(decisions, context: context)
        return CaptureResponse(decisions: decisions)
    }

    // Values from a page that was only hidden were never submitted, so they wait for review.
    private func limitingSaves(_ decisions: [CaptureDecision], request: CaptureRequest, at date: Date)
        -> [CaptureDecision] {
        guard request.trigger == .submit else { return decisions.map(\.reviewInsteadOfSave) }
        let recent = events().captures.count {
            $0.verdict == .saved && date.timeIntervalSince($0.date) < Self.saveWindow
        }
        let allowance = max(0, min(Self.maxSavesPerCapture, Self.maxSavesPerWindow - recent))
        return decisions.reduce(into: (kept: [CaptureDecision](), left: allowance)) { result, decision in
            guard decision.savedValue != nil else { return result.kept.append(decision) }
            result.kept.append(result.left > 0 ? decision : decision.reviewInsteadOfSave)
            result.left -= 1
        }.kept
    }

    // New values go onto the card ranked for this site when Match each site is on, so the
    // value just typed is the one Safari offers here next time. If the card can't be saved
    // they wait for review.
    private func saveToCard(_ decisions: [CaptureDecision], context: CaptureContext) -> [CaptureDecision] {
        let additions = decisions.compactMap(\.savedValue)
        guard !additions.isEmpty else { return decisions }
        let request = context.request
        let page = PageSignal(
            host: request.host, hints: request.hints, now: context.date, matchEachSite: context.matchEachSite
        )
        let usage = context.usage(decisions)
        let sync = syncRequest(context.state, link: context.link, page: page, additions: additions, newUsage: usage)
        let writer = CardWriter(gateway: gateway)
        guard case .failed = writer.sync(sync, current: context.card).outcome else { return decisions }
        return decisions.map(\.reviewInsteadOfSave)
    }

    private func record(_ decisions: [CaptureDecision], context: CaptureContext) {
        let usage = context.usage(decisions)
        let captures = CaptureFilter.captures(from: decisions, host: context.request.host, at: context.date)
        guard !usage.isEmpty || !captures.isEmpty else { return }
        do {
            try store.appendEvents(usage: usage, captures: captures)
        } catch {
            Self.log.error("events not saved: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}

private struct CaptureContext {
    let request: CaptureRequest
    let state: AppState
    let link: CardLink
    let card: CardRecord
    let date: Date

    var matchEachSite: Bool { state.settings.matchEachSite }

    // With Match each site off, Prefill keeps no record of where a value was used.
    func usage(_ decisions: [CaptureDecision]) -> [UsageEvent] {
        matchEachSite ? CaptureFilter.usage(from: decisions, host: request.host, at: date) : []
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
