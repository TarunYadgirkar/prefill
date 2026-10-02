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
