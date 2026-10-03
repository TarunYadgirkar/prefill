import Foundation
import PrefillKit

extension MacModel {
    // Adds a value typed in Chrome or Arc that Prefill wasn't sure about to the card.
    func save(_ item: RecentItem) async {
        guard let link = state.cardLink else { return }
        let value = ContactValue(
            payload: item.value.payload, label: item.value.label, source: .captured, createdAt: .now
        )
        commit(state.unrejecting(value.id).with(values: state.values + [value]))
        let request = CardSyncRequest(
            cardIdentifier: link.contactIdentifier, known: state.values, additions: [value], usage: [], pins: [],
            page: PageSignal(host: nil, hints: [:], now: .now, matchEachSite: false)
        )
        let gateway = gateway
        let outcome = await Task.detached { CardWriter(gateway: gateway).sync(request).outcome }.value
        if case .failed(let failure) = outcome { problem = failure.reason }
        await refresh()
    }

    var customFields: [CustomField] { card?.customFields ?? [] }

    // Returns why the field can't be saved, or nil once it is on the card (or the card
    // couldn't take it, which shows as a problem).
    func saveCustomField(_ field: CustomField, replacing old: CustomField?) async -> String? {
        switch customFields.saving(field, replacing: old) {
        case .failure(let problem): return problem.message
        case .success(let fields):
            await setCustomFields(fields)
            return nil
        }
    }

    func removeCustomField(_ field: CustomField) async {
        await setCustomFields(customFields.filter { $0.id != field.id })
    }

    private func setCustomFields(_ fields: [CustomField]) async {
        guard let identifier = state.cardLink?.contactIdentifier else { return }
        let gateway = gateway
        let outcome = await Task.detached {
            CardEditor(gateway: gateway).apply(.setCustomFields(fields), cardIdentifier: identifier)
        }.value
        if case .failed(let failure) = outcome { problem = failure.reason }
        await refresh()
    }

    // Moves what the person chose off My Card onto Prefill's contact.
    func moveOffCard(_ chosen: [CardExtra]) async {
        guard let identifier = state.cardLink?.contactIdentifier else { return }
        let gateway = gateway
        let failure = await Task.detached { () -> CardWriteFailure? in
            do throws(CardWriteFailure) {
                try gateway.moveOffCard(chosen, identifier: identifier)
                return nil
            } catch {
                return error
            }
        }.value
        if let failure { problem = failure.reason }
        await refresh()
    }

    func dismiss(_ item: RecentItem) {
        commit(state.rejecting(item.value.id))
    }

    var matchEachSite: Bool {
        get { state.settings.matchEachSite }
        set { commit(state.with(settings: settings(matchEachSite: newValue))) }
    }

    var saveNewInfo: Bool {
        get { state.settings.saveNewInfo }
        set { commit(state.with(settings: settings(saveNewInfo: newValue))) }
    }

    var opensAtLoginSetting: Bool {
        get { opensAtLogin }
        set { setOpensAtLogin(newValue) }
    }

    private func settings(matchEachSite: Bool? = nil, saveNewInfo: Bool? = nil) -> PrefillKit.Settings {
        let current = state.settings
        return PrefillKit.Settings(
            matchEachSite: matchEachSite ?? current.matchEachSite, saveNewInfo: saveNewInfo ?? current.saveNewInfo,
            focusLabel: current.focusLabel
        )
    }
}
