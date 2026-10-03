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

    // Puts the person's own order on the card, or with a host that site's order, the way
    // Safari's page context does.
    @discardableResult
    func syncCard(additions: [ContactValue] = [], host: String? = nil) async -> CardWriteOutcome {
        guard let link = state.cardLink else { return .failed(.cardMissing) }
        let request = CardSyncRequest(
            cardIdentifier: link.contactIdentifier, known: state.values, additions: additions,
            usage: host == nil ? [] : events.usage, pins: host == nil ? [] : state.pins,
            page: PageSignal(
                host: host, hints: [:], now: .now, matchEachSite: state.settings.matchEachSite,
                siteKinds: state.siteKinds, focusLabel: state.settings.focusLabel
            )
        )
        let outcome = await CardWork.sync(gateway, request)
        if case .failed(let failure) = outcome { report(failure) }
        await refreshCard()
        return outcome
    }

    var customFields: [CustomField] { card?.customFields ?? [] }

    // Returns why the field can't be saved, or nil once it is on the card (or the card
    // couldn't take it, which the app reports on its own).
    func saveCustomField(_ field: CustomField, replacing old: CustomField?) async -> String? {
        switch customFields.saving(field, replacing: old) {
        case .failure(let problem): return problem.message
        case .success(let fields):
            await edit(.setCustomFields(fields))
            return nil
        }
    }

    func removeCustomField(_ field: CustomField) async {
        await edit(.setCustomFields(customFields.filter { $0.id != field.id }))
    }

    func moveCustomFields(from source: IndexSet, to destination: Int) async {
        var fields = customFields
        fields.move(fromOffsets: source, toOffset: destination)
        await edit(.setCustomFields(fields))
    }

    @discardableResult
    private func edit(_ edit: CardEditor.Edit) async -> Bool {
        guard let link = state.cardLink else { return false }
        let outcome = await CardWork.edit(gateway, edit, identifier: link.contactIdentifier)
        await refreshCard()
        guard case .failed(let failure) = outcome else { return true }
        report(failure)
        return false
    }
}
