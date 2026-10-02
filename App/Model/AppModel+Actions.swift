import Foundation
import PrefillKit

// Everything the person can change. Each change updates the screen first, then the card,
// and re-reads the card afterwards so the screen always ends on what Contacts holds.
extension AppModel {
    // Updates the order right away, so the list and the bar move with the drag, then
    // writes the card in the background.
    func reorder(_ kind: ContactKind, to ordered: [ContactValue]) {
        commit(state.with(values: ManualOrder.replacing(kind, with: ordered, in: state.values)))
        Task { await syncCard() }
    }

    // Returns false when the value is already on the card.
    func add(_ payload: ContactPayload, label: String?, source: ValueSource = .typedInApp) async -> Bool {
        let value = ContactValue(payload: payload, label: label, source: source, createdAt: .now)
        guard !ContactKind.allCases.flatMap(values).contains(where: { $0.id == value.id }) else { return false }
        commit(state.with(values: state.values + [value]))
        await syncCard(additions: [value])
        return true
    }

    func remove(_ value: ContactValue) async {
        guard await edit(.remove(value)) else { return }
        commit(state.with(values: state.values.filter { $0.id != value.id }))
    }

    func relabel(_ value: ContactValue, to label: String?) async {
        guard await edit(.relabel(value, label: label)) else { return }
        let relabeled = state.values.map { $0.id == value.id ? $0.with(label: label) : $0 }
        commit(state.with(values: relabeled))
    }

    func pin(_ value: ContactValue?, kind: ContactKind, on host: String) {
        commit(state.pinning(value?.id, kind: kind, host: host))
    }

    // `label` is what the person picked in Recently added, or the suggestion they kept.
    func save(_ item: RecentItem, label: String?) async {
        _ = await add(item.value.payload, label: label, source: .captured)
    }

    func dismiss(_ item: RecentItem) {
        commit(state.rejecting(item.value.id))
    }

    // Puts a value that was taken off or dismissed back on the card, and lets later forms
    // save it again.
    func putBack(_ item: RecentItem, label: String?) async {
        commit(state.unrejecting(item.value.id))
        _ = await add(item.value.payload, label: label, source: .captured)
    }

    // Takes a saved value off the card and remembers not to save it again.
    func undo(_ item: RecentItem) async {
        guard await edit(.remove(item.value)) else { return }
        commit(state.rejecting(item.value.id).with(values: state.values.filter { $0.id != item.value.id }))
    }

    // Turning it off puts the person's own order back on the card straight away.
    func setMatchEachSite(_ isOn: Bool) {
        let settings = state.settings
        commit(state.with(settings: Settings(
            matchEachSite: isOn, saveNewInfo: settings.saveNewInfo, focusLabel: settings.focusLabel
        )))
        if !isOn { Task { await syncCard() } }
    }

    func setSaveNewInfo(_ isOn: Bool) {
        let settings = state.settings
        commit(state.with(settings: Settings(
            matchEachSite: settings.matchEachSite, saveNewInfo: isOn, focusLabel: settings.focusLabel
        )))
    }

    func restoreOriginalCard() async {
        guard let original = state.cardLink?.original, await edit(.restore(original)) else { return }
        commit(state.with(values: ManualOrder.allValues(card: original, known: state.values, now: .now)))
    }

    func link(_ choice: CardChoice) async {
        do throws(CardWriteFailure) {
            let link = try await contacts.link(choice.id)
            commit(state.with(cardLink: link))
            await refreshCard()
        } catch {
            report(error)
        }
    }

    // Puts the person's own order on the card, with nothing site-specific mixed in.
    private func syncCard(additions: [ContactValue] = []) async {
        guard let link = state.cardLink else { return }
        let request = CardSyncRequest(
            cardIdentifier: link.contactIdentifier, known: state.values, additions: additions, usage: [], pins: [],
            page: PageSignal(
                host: nil, hints: [:], now: .now, matchEachSite: state.settings.matchEachSite,
                focusLabel: state.settings.focusLabel
            )
        )
        if case .failed(let failure) = await CardWork.sync(gateway, request) { report(failure) }
        await refreshCard()
    }

    private func edit(_ edit: CardEditor.Edit) async -> Bool {
        guard let link = state.cardLink else { return false }
        let outcome = await CardWork.edit(gateway, edit, identifier: link.contactIdentifier)
        await refreshCard()
        guard case .failed(let failure) = outcome else { return true }
        report(failure)
        return false
    }
}
