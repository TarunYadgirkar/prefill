import Foundation
import os

extension MessageRouter {
    // A page can only put so much on the card: a few new values per form, and a few more
    // per hour across every site. The rest wait for review, up to a daily limit per site.
    static let maxSavesPerCapture = 3
    static let maxSavesPerWindow = 6
    static let saveWindow: TimeInterval = 3_600
    static let maxReviewsPerSite = 20
    static let reviewWindow: TimeInterval = 86_400

    // Without a linked card there is nothing to compare against and nobody has agreed to
    // anything yet, without the card nothing can be compared either, and on a site the
    // person said not to save on nothing is wanted, so in each case the capture is dropped
    // whole (docs/messages.md, capture).
    func capture(_ request: CaptureRequest) -> CaptureResponse {
        Self.eventLock.withLock { _ in
            let dropped = CaptureResponse(saved: 0, review: 0, ignored: request.fields.count)
            guard let state = currentState(), let link = state.cardLink, !state.isMuted(request.host) else {
                return dropped
            }
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
            let decisions = limitingReviews(saveToCard(evaluated, context: context), host: request.host, at: date)
            record(decisions, context: context)
            return CaptureResponse(decisions: decisions)
        }
    }

    // Values from a page that was only hidden were never submitted, so they wait for review.
    private func limitingSaves(_ decisions: [CaptureDecision], request: CaptureRequest, at date: Date)
        -> [CaptureDecision] {
        guard request.trigger == .submit else { return decisions.map(\.reviewInsteadOfSave) }
        let stored = events()
        let isRecent = { (saved: Date) in date.timeIntervalSince(saved) < Self.saveWindow }
        // Records written before `saves` existed still count.
        let recent = max(
            stored.saves.count(where: isRecent),
            stored.captures.count { $0.verdict == .saved && isRecent($0.date) }
        )
        let allowance = max(0, min(Self.maxSavesPerCapture, Self.maxSavesPerWindow - recent))
        return decisions.reduce(into: (kept: [CaptureDecision](), left: allowance)) { result, decision in
            guard decision.savedValue != nil else { return result.kept.append(decision) }
            result.kept.append(result.left > 0 ? decision : decision.reviewInsteadOfSave)
            result.left -= 1
        }.kept
    }

    // A site that keeps filing values for review stops being heard for a day, so it can't
    // bury the person's other captures.
    private func limitingReviews(_ decisions: [CaptureDecision], host: String, at date: Date) -> [CaptureDecision] {
        let site = Normalizer.registrableDomain(host)
        let waiting = events().captures.count {
            $0.host == site && $0.verdict == .needsReview && date.timeIntervalSince($0.date) < Self.reviewWindow
        }
        return decisions.reduce(into: (kept: [CaptureDecision](), left: Self.maxReviewsPerSite - waiting)) {
            guard case .review = $1 else { return $0.kept.append($1) }
            $0.kept.append($0.left > 0 ? $1 : .ignore(.tooMany))
            $0.left -= 1
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
            host: request.host, hints: request.hints, now: context.date, matchEachSite: context.matchEachSite,
            siteKinds: context.state.siteKinds, focusLabel: context.state.settings.focusLabel
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
        let saves = Array(repeating: context.date, count: decisions.count { $0.savedValue != nil })
        guard !usage.isEmpty || !captures.isEmpty else { return }
        append(ExtensionEvents(usage: usage, captures: captures, saves: saves))
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
