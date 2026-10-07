import Foundation
import PrefillKit

// What Siri, Shortcuts and Focus ask of the app. Values go back to the system only as the
// intent's result; nothing here logs them.
extension AppModel {
    func ranked(_ kind: ContactKind, host: String?) -> [ContactValue] {
        ValueLookup.ranked(values(kind), host: host, state: state, events: events, now: .now)
    }

    func siteHosts(matching text: String?) -> [String] {
        ValueLookup.sites(matching: text, state: state, events: events)
    }

    // Puts `id` first: pinned on `host`, or at the top of the person's own order when no
    // site is named. Returns nil when the value is no longer on the card.
    func promote(_ id: UUID, kind: ContactKind, host: String?) async -> CardWriteOutcome? {
        let order = values(kind)
        guard let value = order.first(where: { $0.id == id }) else { return nil }
        if let host {
            commit(state.pinning(id, kind: kind, host: host))
        } else {
            let reordered = [value] + order.filter { $0.id != id }
            commit(state.with(values: ManualOrder.replacing(kind, with: reordered, in: state.values)))
        }
        return await syncCard(reportsProblem: false)
    }

    // A nil label is a Focus turning off, which puts the person's own order back.
    func setFocusLabel(_ label: String?) async -> CardWriteOutcome {
        let settings = state.settings
        commit(state.with(settings: Settings(
            matchEachSite: settings.matchEachSite, saveNewInfo: settings.saveNewInfo, focusLabel: label
        )))
        return await syncCard(reportsProblem: false)
    }
}
